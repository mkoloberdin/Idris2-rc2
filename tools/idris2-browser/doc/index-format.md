# idris2-browser: index format

The index that `idris2-browser-index` writes is a public interface. Any
front end may read it: `idris2-browser` itself, and later an editor plugin
(for example one for Neovim, which can read it with `vim.json.decode`). This
file is the specification. `design.md` says why the index exists and how it is
built.

Status: format version 1, written by `idris2-browser-index` 0.1.0.

## Rules for readers

- Every file is UTF-8 JSON. Every top-level object has `"formatVersion"`.
  - A reader must refuse a major version it does not know.
  - It must ignore fields it does not know: new fields are added without a
    version change.
  - A field is removed or changes meaning only with a new `formatVersion`.
- A reader never writes into the index directory and needs no lock.
  - Writers replace each file as a whole: they write a temporary file in the
    same directory and rename it.
  - So a reader sees either the old file or the new one, never a mix.
- Files can be from different runs. For example, a module file may be newer
  than `packages.json`. Each file is self-describing, so a reader can use it
  on its own.
  - A reader that finds a `key` in `packages.json` without its `pkg/<key>/`
    directory treats the package as not indexed yet.
- To find the index directory, run `idris2-browser-index --print-index-dir`
  (see "Command line"). Do not re-implement the default.

## Layout

```
<index dir>/
  env.json
  packages.json
  pkg/<key>/summary.json
  pkg/<key>/mod/<Module.Name>.json
  .lock/                        writers only (see "Command line")
```

- `<key>` is `<name>-<version>-<hash>`. `<hash>` is the first 8 hex digits
  of a hash of the package's absolute directory, and the version part is empty
  for a package without one.
- `<Module.Name>` is the module name with its dots, for example
  `pkg/base-0.8.0-1a2b3c4d/mod/Data.List.json`.

## Common values

| name | JSON | meaning |
|---|---|---|
| path | string | absolute file path |
| time | string | UTC, RFC 3339, e.g. `"2026-11-23T10:00:00Z"` |
| pos | `[line, column]` | both 0-based, as in Idris 2's `FC` |
| visibility | `"private"`, `"export"`, `"public export"` | |
| totality | `"total"`, `"covering"`, `"partial"` | `"covering"` also when termination was not checked, as without `%default total`; that includes data, constructors and foreign definitions only when Idris did not mark them total |
| kind | `"data"`, `"record"`, `"interface"`, `"constructor"`, `"function"`, `"foreign"`, `"builtin"`, `"hole"`, `"other"` | |

## env.json

The environment the last run surveyed.

```json
{
  "formatVersion": 1,
  "indexer": { "version": "0.1.0", "idris2Version": "0.8.0",
               "ttcVersion": 2025081600 },
  "prefix": "/home/me/idris2",
  "prefixFrom": "idris2-on-path",
  "searchDirs": [
    { "path": "/home/me/pkgs", "from": "IDRIS2_PACKAGE_PATH" },
    { "path": "/home/me/idris2/idris2-0.8.0", "from": "prefix" }
  ],
  "updated": "2026-11-23T10:00:00Z"
}
```

- `prefixFrom` is one of:
  - `"option"`: `--prefix`;
  - `"idris2-on-path"`: `idris2 --prefix`;
  - `"IDRIS2_PREFIX"`;
  - `"builtin"`: the prefix `idris2api` was built with.
- `searchDirs` is in search order.

## packages.json

```json
{
  "formatVersion": 1,
  "packages": [
    {
      "key": "contrib-0.8.0-1a2b3c4d",
      "name": "contrib",
      "version": "0.8.0",
      "dir": "/home/me/idris2/idris2-0.8.0/contrib-0.8.0",
      "searchDir": "/home/me/idris2/idris2-0.8.0",
      "selected": true,
      "status": "ok",
      "ttcVersions": [2025081600],
      "ipkg": {
        "file": "/home/me/idris2/idris2-0.8.0/contrib-0.8.0/contrib.ipkg",
        "version": "0.8.0",
        "brief": null, "authors": null, "license": null,
        "sourcedir": null,
        "depends": [ { "name": "base", "bounds": "" } ],
        "modules": [],
        "main": null, "executable": null
      },
      "sources": "none"
    }
  ]
}
```

- **version**: from the directory name, `null` if it has none.
- **selected**: the copy `idris2` would pick for an unconstrained `depends`
  on this name.
- **status** is one of:
  - `"ok"`;
  - `"no-ipkg"`: listed from its directory only, `ipkg` is `null`;
  - `"unreadable"`: there is no `<ttcVersion>` directory of the indexer's
    version; `ttcVersions` lists the ones found.
- **ipkg**: the fields of the installed `.ipkg`.
  - `idris2 --install` writes a reduced copy that keeps only the name, the
    version and `depends`, and comments the other fields out. So for an
    installed package the other fields are normally `null` or empty. The
    modules of a package are its module files, not `ipkg.modules`.
  - Strings the ipkg does not set are `null`.
  - `bounds` is the version bounds as written, `""` for none.
- **sources** says where the module sources are, which "Source locations"
  uses:
  - `"installed"`: the package was installed with `--install-with-src`, and
    the sources are under `dir`;
  - `"none"`: only TTC files are installed.

## pkg/\<key\>/summary.json

```json
{
  "formatVersion": 1,
  "key": "contrib-0.8.0-1a2b3c4d",
  "stats": {
    "modulesFound": 120, "modulesFailed": 0,
    "ttcBytes": 5242880,
    "definitions": { "function": 900, "data": 40, "record": 12,
                     "interface": 8, "constructor": 130 },
    "visibility": { "private": 300, "export": 500, "public export": 290 },
    "totality": { "total": 800, "covering": 200, "partial": 90 },
    "exportedWithDoc": 410, "exported": 790,
    "modulesWithDoc": 30
  },
  "names": [
    ["Data.List.Extra.nubOrd", "Data.List.Extra", "function",
     "export", true]
  ]
}
```

- `names` has one row per definition:
  `[full name, module, kind, visibility, has doc]`.
  - It is meant for search across the environment without opening module
    files.
  - Rows are in the order of the module files (a directory walk of the
    TTCs), then in source order.
- `exported` counts `export` and `public export`.
- Reverse dependencies are not stored. A reader derives them from the
  `depends` of `packages.json`.

## pkg/\<key\>/mod/\<Module.Name\>.json

```json
{
  "formatVersion": 1,
  "key": "contrib-0.8.0-1a2b3c4d",
  "module": "Data.List.Extra",
  "ttc": { "path": "/home/me/.../2025081600/Data/List/Extra.ttc",
           "bytes": 40960, "mtime": "2026-11-20T09:00:00Z" },
  "status": "ok",
  "error": null,
  "doc": "Extra functions on lists.",
  "imports": [ { "module": "Data.List", "public": false,
                 "as": "Data.List" } ],
  "definitions": [
    {
      "name": "Data.List.Extra.nubOrd",
      "kind": "function",
      "visibility": "export",
      "totality": "total",
      "type": "Ord a => List a -> List a",
      "doc": "Remove duplicates, keeping the first.",
      "location": { "module": "Data.List.Extra",
                    "start": [12, 0], "end": [12, 34] }
    }
  ]
}
```

- **status**: `"ok"` or `"failed"`.
  - When it is `"failed"`, `error` holds the message and `definitions` is
    empty.
- **doc**: the module's doc comment, `null` if it has none. The same holds for
  each definition's `doc`.
- **type**: printed with only this module's own fixities in scope, so an
  operator from an import may appear in prefix form.
- **definitions**: the names the module's source defines at the top of a
  namespace: types, constructors, functions, record projections, interfaces
  and their methods. Implementations, `where` helpers, case blocks and other
  names Idris makes are left out, and so is anything without a source
  position.
- **location**: always set in format 1 (see **definitions**); a reader should
  still accept `null`.

## Source locations

A TTC records a definition's position as a module name and two `pos` values,
not as a file path. A reader that wants to open the source finds the file like
this:

1. Pick a root:
   - if `sources` is `"installed"`, the root is the package `dir`;
   - otherwise the reader needs a root from the user, such as a checkout of
     the package or a project's `depends/` copy. The installed ipkg has no
     `sourcedir` (see `ipkg` above), so the root is joined with the
     `sourcedir` of the `.ipkg` found in that checkout, when it sets one.
2. The file is `<root>/<module path>.<ext>`.
   - `<module path>` is the module name with `.` replaced by `/`.
   - `<ext>` is the first that exists of `idr`, `lidr`, `md`, `org`, `tex`
     (Idris 2's literate formats).

Positions are 0-based, while Neovim's `nvim_win_set_cursor` takes a 1-based
line and a 0-based column, so add 1 to the line only.

## Command line

The part of `idris2-browser-index` that front ends rely on:

| command | effect |
|---|---|
| `--print-index-dir` | print the index directory and exit |
| `--update` | bring the index up to date (only changed modules are re-read) |
| `--update --json` | the same, with progress as JSON lines on stdout |
| `--update --pretty` | the same, writing indented JSON (for reading and diffs) |
| `--index-dir DIR` | use DIR instead of the default |
| `--prefix DIR` | survey this prefix instead of the default |

The exit code is 0 when the run finished, even if some modules failed (they are
recorded with `"status": "failed"`). It is 1 when the run itself failed, for
example on a bad option or a file of the index that could not be written,
and 2 when another writer holds the lock.

`--json` lines:

```json
{"event": "start", "indexDir": "...", "packages": 25}
{"event": "package", "key": "...", "modules": 120}
{"event": "module", "key": "...", "module": "Data.List.Extra", "result": "updated"}
{"event": "done", "updated": 3, "unchanged": 1200, "failed": 0, "removed": 0}
```

- A `module` event's `result` is `"updated"`, `"unchanged"` or `"failed"`; a
  failed one also has `"error"`.
  - A module reported `"unchanged"` is reported again, `"updated"`, when its
    file turns out unreadable while the summary is rebuilt. The counts of
    `done` count it once.
- A package whose TTCs are unreadable gets no `package` event.
- Human-readable messages go to stderr in both modes.

Writers take the lock `<index dir>/.lock/` and remove it at the end:
- A writer makes `<index dir>/.lock.<pid>/` with a `pid` file in it and
  renames it to `.lock`. The rename fails while another lock is there, so a
  lock that can be seen always names its holder.
- A lock whose process no longer exists (looked up in `/proc`, so on Linux
  only) is renamed out of the way, which only one writer can do, and taken
  again.
