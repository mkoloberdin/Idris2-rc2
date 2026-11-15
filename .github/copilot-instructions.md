# Instructions for reviewing this repository

rc2 is an independent C code generator backend for Idris 2 (`rc2/src/Compiler/RC2/*.idr` is the
compiler, `rc2/support/rc2/*.c|*.h` the runtime, `libs/` Idris and C libraries,
`rc2/tests/` the regression suite, `rc2/doc/*.md` one design note per pass). `idris2-src/` is an
untouched upstream checkout and is not part of a change.

## What matters in a review

- **Reference counting.** rc2 inserts explicit `RDup`/`RDrop`/`RFree` once, in `Compiler.RC2.RC`.
  A pass that moves, merges or removes them must keep every path's ownership balanced: look for
  a missing drop (a leak), an extra one (use after free), and a dup of a value that is moved.
- **The C runtime.** Undefined behaviour, integer overflow in size computations, missing `NULL`
  checks after allocation, data races (the runtime is multi-threaded: reference counts are
  non-atomic until a second thread starts), and strings that are not NUL-terminated or contain NUL.
- **A pass is sound before it is fast.** A rewrite that changes evaluation order, sharing or the
  number of times an expression runs needs a stated reason (several are opt-in directives for that).
- **Tests.** A change to a pass or the runtime comes with a test under `rc2/tests/TestN*/`
  (`.idr` + `.expected`, optionally a `check.sh` that asserts on the generated IR or C). A new
  behaviour that no test reaches is worth saying so.
- **Documentation.** A pass or directive has a note in `rc2/doc/`; `rc2/doc/directives.md`
  lists the directives.

## Conventions

- Idris code follows `code-style.md` and `code-style-Idris2.md`, C follows `code-style-C.md`.
- Comments and documentation are in English.
- Measured numbers (instructions, seconds, bytes) in a description should say what was measured
  and against what.

Do not flag generated files, `rc2/tests/**/*.expected`, or the vendored `idris2-src/`.
