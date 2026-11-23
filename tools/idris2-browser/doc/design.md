# idris2-browser: design

A terminal browser for the Idris 2 packages installed in an environment: the
list of packages with statistics, and for each package its modules, the
definitions of each module with their types, and the doc comments. The purpose
is to survey an environment, so by default it looks at what the `idris2` on
`PATH` would see, and follows the environment variables when they are set.

Status: the indexer and the browser are implemented; see "Open points".

## Goals and non-goals

First version:

- List every package found in the environment, with its version, its
  directory, the search path it came from and the data of its installed
  `.ipkg` (its dependencies).
- Statistics per package and for the whole environment (see "Statistics").
- Per module: the module's doc comment and its definitions, each with its kind,
  visibility, totality, type and doc comment.
- Incremental search over the definition names of the whole environment, and
  filters on visibility and on "has no doc comment".

Not in the first version:

- Jumping to a definition's source (the index keeps the location, so this can
  be added without changing the format).
- Types printed with the fixities and sugar of the module's imports. A module
  is read alone, so a type is printed with only that module's own fixities and
  may come out in prefix form (see "Reading a module").
- Local `depends/` directories of a project.

## Architecture

Two programs that share an index on disk:

```
idris2-browser-index  (Chez; idris2api + contrib)
    reads   <search dirs>/<pkg>-<ver>/<ipkg>, <ttcVersion>/**/*.ttc
    writes  <index dir>/...                       (JSON, see "Index")

idris2-browser        (rc2; termui + rc2base + control-async + contrib)
    reads   <index dir>/...
    runs    idris2-browser-index --update  at start-up
```

Why two programs:

- Reading a TTC needs `idris2api`, and the reader must be the same version as
  the compiler that wrote the TTC. The stable build of `idris2api` is the Chez
  one; building it with rc2 is still the self-hosting experiment
  (`rc2/doc/self-hosting.md`). `termui` is rc2-only. Splitting puts each half
  on the backend it already works on.
- Decoding definitions is the expensive part of reading a TTC (#363 measured
  it). The index turns that into a one-time cost per changed module, and makes
  whole-environment statistics and search cheap.
- The TTC version stays a concern of the indexer only. The index format is
  ours, so the indexer can later be built with rc2 without touching the browser.

Neither program depends on `notcurses`; `termui` writes plain ANSI.

## Finding the packages

The indexer does what `idris2` does in `Idris.Driver.updateEnv` and
`Idris.SetOptions.findPackages` (neither is exported, so this is a small
re-implementation, not a call):

1. The prefix is what `idris2 --prefix` prints for the `idris2` on `PATH`. That
   value already follows `IDRIS2_PREFIX`.
   - With no `idris2` on `PATH`, the indexer falls back to the prefix
     `idris2api` was built with, after `IDRIS2_PREFIX`.
   - A `--prefix` option overrides both.
   - When the toolchain on `PATH` has another TTC version than the indexer's,
     its packages are still listed, as unreadable, with their ipkg data.
2. The search dirs are the entries of `IDRIS2_PACKAGE_PATH` (split as
   `splitPaths` does), in order, followed by `<prefix>/idris2-<version>`.
3. In each search dir, every subdirectory whose name parses as `<name>` or
   `<name>-<version>` is a package, except hidden ones and `include`, `lib`,
   `support`, `refc` (upstream's deny list).

Several versions of one package, or one package in several search dirs, are
all listed. The one `idris2` would pick for an unconstrained `depends` is
marked as selected.

For each package:

- Its `.ipkg` is parsed with `idris2api`'s own package parser.
  - `idris2 --install` writes a reduced copy of the ipkg into the package
    directory. It keeps only the name, the version and `depends`, so modules,
    `sourcedir`, authors and the like are normally absent.
  - A package without one is listed with its directory only.
- Its modules are the `.ttc` files under `<pkgdir>/<ttcVersion>/`.
  - A package with no `<ttcVersion>` directory, only other version
    directories, is listed as "unreadable: built by TTC version N".
  - Its ipkg data is still shown.
- Its sources count as installed when the source of its first module exists
  under the package directory, which is where `--install-with-src` puts them.

## Reading a module

Each module is read into a fresh context, with no imports:

1. `readFromTTC` with the module's TTC.
   - This adds the module's definitions to the context still encoded.
   - It returns the module's `SyntaxInfo`, the TTC's `extraData`.
2. The module's own definitions are the context entries whose location's
   origin is this module, as `--mkdoc` selects them in
   `Idris.Package.makeDoc`, and whose name is a user name at the top of a
   namespace (`NS _ (UN _)`). The second rule leaves out implementations,
   `where` helpers, case blocks and the other names Idris makes.
   - Private ones are kept and marked as such; hiding them is a browser filter.
3. Per definition, the indexer records:
   - An entry is decoded with `decode ctx idx False entry`, not
     `lookupCtxtExact`, which writes the decoded entry back into the context
     (#363).
   - **name**: the full name.
   - **kind**:
     - a `TCon` named in `ifaces` is an interface;
     - a `TCon` is a record when `Idris.Doc.String.getFieldsDoc` would find
       fields, and data otherwise;
     - the other kinds are constructor, function (`PMDef`), foreign, builtin
       and hole.
     - The rule is the same one `:doc` uses (`getExtra` in
       `Idris/Doc/String.idr`).
   - **visibility**, **totality**.
   - **type**: printed from the decoded type with only this module's fixities
     in scope.
   - **doc**: from `defDocstrings` in the `SyntaxInfo`. A TTC holds the doc
     comments of the names its own module defines (`saveDocstrings` in
     `TTC SyntaxInfo`), so no import is needed for this.
   - **location**: the module and the start and end positions, kept for a
     later "jump to source". A TTC has no file path here.
4. The module doc is `modDocstrings` in the `SyntaxInfo`. The imports are the
   TTC's `imported` list.

A fresh context per module keeps memory flat and makes one module's failure
local: it is recorded in the index as an error and the run goes on.

## Index

The index lives in one directory. It defaults to
`$XDG_CACHE_HOME/idris2-browser`, with `~/.cache/idris2-browser` as the
fallback, and `--index-dir` overrides it. Tests and development runs always
pass `--index-dir` under their own `build/`, so they never write outside the
repository.

The index is a public interface, not a private file of the browser. Its
specification, with every file and field, the reader rules and the command
line front ends rely on, is [`index-format.md`](index-format.md). In short:

```
<index dir>/
  env.json                      prefix, search dirs, TTC version, time
  packages.json                 one entry per package
  pkg/<key>/summary.json        statistics + name table for search
  pkg/<key>/mod/<Module>.json   one file per module
```

- The browser loads every `summary.json` at start-up, for global search and
  the statistics view, and opens a module file when that module is selected.
- `--update` re-reads a module only when its TTC is at least as new as its
  module file, the rule of `make`. So an unchanged environment costs a `stat`
  per module and no JSON parsing.
  - A package's `summary.json` is re-written only if one of its modules
    changed or was removed. Packages that are gone are removed.
  - The rule cannot see a change in the indexer itself, so `pkg/` is rebuilt
    whole when `env.json` is missing or names another `formatVersion`,
    indexer version or TTC version. The indexer's version is bumped whenever
    what it extracts changes.
  - A module that failed to read is not retried until its TTC or the indexer
    changes: the same TTC fails the same way.
  - A module file that no longer parses is read again from its TTC, but only
    when the summary is rebuilt.
  - Before a module file changes, the package's summary is removed, so a run
    stopped before the summary is written leaves none and the next run
    rebuilds it.
  - The rule trusts file times. A TTC copied with its old time kept (`cp -p`,
    `tar`) over an indexed one is not seen; one with a time in the future is
    read again on every run.
  - Each module file also records the TTC's size and mtime, for readers.

The schema (`IdrisBrowser.Schema`) and its JSON (`IdrisBrowser.JSON`) are
modules that both programs build, depending only on `contrib`.
- `rc2base` is not usable by the indexer, because a Chez-built program must
  not depend on it.
- `contrib`'s own `Language.JSON` renderer is not used either. It escapes
  every non-ASCII character through a `Bits16`, which breaks characters
  outside the BMP, and it builds text with `concatMap`.

## Other front ends

The index is designed so that a front end other than `idris2-browser`, for
example a Neovim plugin, can be written later without changing the indexer:

- **Plain JSON with a version.** Every file carries `formatVersion`.
  - A reader ignores fields it does not know, so fields can be added freely.
  - Removing a field or changing its meaning needs a new version.
- **No re-implemented defaults.** `idris2-browser-index --print-index-dir`
  prints the index directory, so a plugin does not copy the rule above.
- **Machine-readable updates.** `--update --json` reports progress as JSON
  lines, so an editor can run it as a job and show the progress.
  - The exit code tells "finished", "failed" and "another writer holds the
    lock" apart.
- **Safe when several front ends run.** A writer replaces each file by
  writing a temporary file in the same directory and renaming it, and takes a
  lock directory, so the browser and an editor can both run `--update`.
  - Readers need no lock.
- **Source positions that can be resolved.** A TTC holds a definition's
  position as a module name and 0-based line and column, not a file path.
  - For each package the index says whether its sources were installed
    (`--install-with-src` puts them under the package directory).
  - The installed ipkg is a reduced copy without `sourcedir` (see "Finding
    the packages"), so for a checkout the front end reads the checkout's own
    ipkg.
  - With that, a front end can open the file when the sources are installed,
    or when the user names a checkout of the package. How the path is
    resolved is in `index-format.md`, "Source locations".

What the browser itself needs from the index is exactly this public part; it
has no side channel.

## Statistics

| figure | per package | needs a TTC decode |
|---|---|---|
| modules found as TTC, modules that failed | yes | no |
| TTC size in total | yes | no |
| dependencies, reverse dependencies | yes | no (ipkg) |
| definitions by kind | yes | yes |
| definitions by visibility | yes | yes |
| doc coverage of exported definitions (%), modules with a module doc | yes | yes |
| totality: covering / partial counts | yes | yes |

The environment view sums them over the selected packages. It also lists the
packages that are unreadable, have no ipkg, or are installed in more than one
version.

## User interface

```
┌──────────────────┐┌─────────────────────┐┌──────────────────────────┐
│Packages          ││Modules              ││Definitions (exported)    │
│  base 0.8.0      ││  Data.List          ││> fn   sortBy             │
│> contrib 0.8.0   ││> Data.List.Extra    ││  fn   nub                │
│  stale 0.1.0 !   ││  ...                ││  ...                     │
└──────────────────┘└─────────────────────┘└──────────────────────────┘
 Doc │ Type │ Stats │ Package
┌─────────────────────────────────────────────────────────────────────┐
│ (MarkdownView)                                                      │
└─────────────────────────────────────────────────────────────────────┘
F1 Doc F2 Type F3 Stats F4 Package F5 Filter F6 Search F10 Quit
```

- **Top half**: three `Select` lists side by side, in proportion 2 : 3 : 4.
  - A `Splitter` is not used: it needs the mouse to move, and the
    proportions serve.
  - Moving in one list fills the lists to its right. A new module's file is
    read then, with `Perform`.
  - After a package name, `!` marks an unreadable package and `~` a copy that
    `idris2` would not pick.
  - A definition is shown as its kind (`data`, `rec`, `ifc`, `con`, `fn`,
    `ffi`, ...) and its name without the module, with `(private)` after a
    private one.
- **Bottom half**: a `TabStrip` over a `MarkdownView`. The pane is filled
  again on every move, so nothing in it folds.
  - **Doc**: the selected definition's type and doc comment, then the
    module's doc comment. Idris doc comments are Markdown.
  - **Type**: the full name and type, the kind, visibility, totality and
    line.
  - **Stats**: the statistics of the selected package, then those of the
    environment, the packages that are not usable and the packages installed
    more than once.
  - **Package**: the directories, the status, whether `idris2` picks it,
    the sources, the TTC versions, what it depends on and what installed
    package depends on it.
- **Bottom line**: a `KeyGuide`.
- **Keys**:
  - F1 to F4 choose the tab;
  - F5 or `f` cycles the filter: exported, all, exported without doc;
  - F6 or `/` opens the search;
  - F10, `q`, Esc or Ctrl-C quit;
  - Tab moves between the lists and the pane.
- **Search**: a `TextInput` over a list of hits. Each keystroke searches the
  definition names of every summary (case-insensitive substring, at most 500
  hits). Enter jumps to the hit: the package, then the module, then the
  definition. When the filter would hide that definition, the filter changes
  to all. Esc closes the search.

At start-up the browser runs `idris2-browser-index --update` and the indexer's
progress goes to the terminal before the screen opens.
- `--indexer PATH` names the indexer, `--index-dir DIR` is passed on to it,
  and `--no-update` skips the update.
- A failed update is only a warning; the browser then shows the index as it
  is. Without a readable `packages.json` it says how to build the index.

`--dump W H [ACTION...]` draws the screen at W by H cells into text after
the actions, without a terminal, for the tests. The actions are `pkg-down`,
`mod-down`, `def-down`, `filter`, `tab:N`, `search`, `type:TEXT` and
`jump`.

## Layout

```
tools/idris2-browser/
  README.md
  doc/design.md                 this file
  doc/index-format.md           the index specification
  index.ipkg                    idris2-browser-index; depends idris2, contrib
  browser.ipkg                  idris2-browser; depends contrib, rc2base,
                                control-async, termui
  src/IdrisBrowser/JSON.idr     shared: JSON rendering and parsing
  src/IdrisBrowser/Schema.idr   shared: index records and their JSON
  src/IdrisBrowser/Stats.idr    shared: module files -> statistics, sums
  src/IdrisBrowser/Index/Files.idr      times, atomic writes, the lock
  src/IdrisBrowser/Index/Discover.idr   search dirs, package dirs, ipkg
  src/IdrisBrowser/Index/ReadTTC.idr    one module -> Schema records
  src/IdrisBrowser/Index/Update.idr     incremental update of the index dir
  src/IdrisBrowser/Index/Main.idr       the indexer's command line
  src/IdrisBrowser/Load.idr     reading the index
  src/IdrisBrowser/App.idr      the browser's model, update and view
  src/IdrisBrowser/Main.idr     the browser's command line, `--dump`
  tests/verify.sh
  tests/fixture/                a small package with docs, a record, an
                                interface, private, covering, partial and
                                foreign definitions, an operator
  tests/expected/               the index files, events and screens
```

## Tests

`tests/verify.sh` follows `tools/rcexpr-lint/tests/verify.sh`: expected output
in text files under `tests/expected/`, judged by `diff` only
(`--accept` rewrites them). Its header comment lists every step.

1. **The fixture**: installed with `idris2 --install-with-src` into a prefix
   under `tests/build/`, which gives the same reduced ipkg and source layout a
   real install has. A directory of another TTC version stands for an
   unreadable package. Every TTC gets a fixed mtime.
2. **Indexer**:
   - run with `--prefix` at an empty prefix and `IDRIS2_PACKAGE_PATH` at the
     fixture's, which tests the environment-variable path;
   - every index file and the `--json` events are compared after masking
     paths, key hashes, TTC sizes and the update time;
   - a second run after touching one TTC re-reads only that module, and the
     summary it rebuilds from the other module's parsed file equals the
     first, which checks the JSON round trip;
   - a third run with another indexer version in `env.json` re-reads all;
   - a fourth, with the lock held by a live process, exits with 2.
3. **Browser**: built with rc2, it draws screens at 100 by 30 with `--dump`
   from a copy of the index whose paths are a fixed `/fixture` (a long path
   wraps where it meets the edge, so masking after drawing would not do).

## Open points

- Types are printed with only the module's own fixities, and implicit
  arguments of applied functions show (`mapMaybe b a f`). Resugaring them as
  `:doc` does needs the module's imports.
- A record's projections appear twice, as `(.x)` and as `x`, as both exist.

## Measurements

The indexer over this repository's `install/`: 25 packages, 925 modules,
including `idris2api` (292 modules, 8,286 definitions).

| run | time | written |
|---|---|---|
| from an empty index | 26 s | 12 MB |
| again, nothing changed | 0.7 s | nothing |

- A module is read in 0.1 to 0.2 s. Most of it is decoding the definitions:
  a type cannot be had without decoding the whole definition, because in a
  `GlobalDef` the type comes after the definition (#363).
- If the first run is too slow, packages can be indexed in parallel
  processes.

The browser (rc2) reads `packages.json` and every `summary.json` (2.4 MB,
25,940 names) in 0.13 s, and draws its first screen in about as long. The
line-based name table once kept in reserve is not needed.
