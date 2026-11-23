# idris2-browser

*[日本語](README.ja.md)*

A terminal browser for the Idris 2 packages installed in an environment: the
packages with their statistics, the modules of each, the definitions of each
module with their kinds, types and doc comments, and a search over every
definition name.

```
┌──────────────────┐┌─────────────────────┐┌──────────────────────────┐
│Packages          ││Modules              ││Definitions (exported)    │
│  base 0.8.0      ││  Data.List          ││> fn   sortBy             │
│> contrib 0.8.0   ││> Data.List.Extra    ││  fn   nub                │
└──────────────────┘└─────────────────────┘└──────────────────────────┘
 Doc │ Type │ Stats │ Package
┌─────────────────────────────────────────────────────────────────────┐
│ the doc comment, the type, the statistics or the package data       │
└─────────────────────────────────────────────────────────────────────┘
F1 Doc F2 Type F3 Stats F4 Package F5 Filter F6 Search F10 Quit
```

It is two programs:

- `idris2-browser-index` reads the installed TTC files with `idris2api` and
  writes an index of JSON files. It is built with the default (Chez) backend
  and must be the same Idris 2 version as the compiler that wrote the TTCs.
- `idris2-browser` is the screen, built with rc2 and `termui`. It brings the
  index up to date by running the indexer, then reads only the index.

The index is a public format ([`doc/index-format.md`](doc/index-format.md)),
so other front ends, an editor plugin for example, can read it too. The
design, the rules for finding packages and the measurements are in
[`doc/design.md`](doc/design.md).

## What it looks at

What the `idris2` on `PATH` would see: the prefix `idris2 --prefix` prints
(which follows `IDRIS2_PREFIX`), and before it the directories of
`IDRIS2_PACKAGE_PATH`. Packages of another TTC version are listed as
unreadable.

## Build

```sh
source ../../env.sh
idris2 --build index.ipkg                                  # build/index/exec/idris2-browser-index
../../rc2/build/exec/idris2-rc2 --cg rc2 --build browser.ipkg   # build/browser/exec/idris2-browser
```

## Use

```sh
build/browser/exec/idris2-browser --indexer build/index/exec/idris2-browser-index
```

| option | effect |
|---|---|
| `--index-dir DIR` | the index directory (default `$XDG_CACHE_HOME/idris2-browser`, else `~/.cache/idris2-browser`) |
| `--indexer PATH` | the indexer to run (default `idris2-browser-index` on `PATH`) |
| `--no-update` | show the index as it is |
| `--dump W H [ACTION...]` | draw the screen into text, for the tests |

The first index of a whole environment takes a while (26 s for 925 modules);
after that only changed modules are read again (0.7 s when nothing changed).

Keys: F1 to F4 choose the tab, F5 or `f` the filter (exported, all, exported
without doc), F6 or `/` searches, Enter jumps to a hit, Tab moves between the
lists, F10, `q` or Esc quit.

The indexer alone:

```sh
idris2-browser-index --update [--json] [--pretty] [--index-dir DIR] [--prefix DIR]
idris2-browser-index --print-index-dir
```

## Test

```sh
tests/verify.sh            # check
tests/verify.sh --accept   # rewrite tests/expected/ from this run
```

It needs `rc2/build/exec/idris2-rc2`, and writes only under `tests/build/`.
