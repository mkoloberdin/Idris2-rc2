# Upstream's tail-recursive list functions, replaced (`Compiler.RC2.ListDivert`)

Off by default; `--directive listdivert` (or `%cg rc2 listdivert` in the program) turns it on.
Whole-program compiles only.

## The problem

`Prelude.Types` rewrites the list functions that recurse under a `::` into tail-recursive
ones, with `%transform` rules, for the backends whose stack a long list would overflow:

| source | at run time | passes | cells |
|---|---|---|---|
| `xs ++ ys` | `tailRecAppend`: `reverseOnto ys (reverse xs)` | 2 over `xs` | 2n, n of them an intermediate list |
| `map f xs` | `mapTR`: `mapAppend [<] f xs`, then `<>>` | 2 | 2n |
| `filter p xs` | `filterTR`: `filterAppend` then `<>>` | 2 | 2k |
| `mapMaybe f xs` | `mapMaybeTR` | 2 | 2k |

rc2 has `Compiler.RC2.Trmc` (`trmc.md`): the naive `x :: f xs` is one loop that fills the
hole of each cell, n cells, constant stack. Under rc2 the upstream rules only double the
allocation and the `teardown` of every `++`, `map`, `filter` and `mapMaybe`. In the case
trees of `rc2-norepl` the `++` shape appears 815 times, `mapAppend` 2,086, `mapMaybeAppend`
185, `filterAppend` 132.

## The pass

`applyListDivert`, on the named case trees right after `applyLazyCaf` and before
`InlineCExp` (`Compiler.RC2.RC2`): every call of an upstream helper becomes a call of a
definition of rc2's own, added to the program when used,

- `tailRecAppend xs ys`, and the shapes the inliner leaves of it (`reverseOnto ys
  (reverseOnto [] xs)`, `reverseOnto ys (reverse xs)`), to `rc2_append xs ys`;
- `mapAppend [<] f xs` (`mapTR` is `%inline`, so this is what the frontend leaves) to
  `rc2_map f xs`, and `filterAppend`/`mapMaybeAppend` with `[<]` to `rc2_filter`/`rc2_mapMaybe`.

The four definitions are the naive ones, in the shape TRMC takes (the recursive call the last
field of the `::`; `filter` and `mapMaybe` mix a plain tail call in, which TRMC's phase 1
covers). A `Bool` alternative is a `B8` constant, as upstream's `Compiler.Opts.Constructor`
makes enum constructors. `SnocList`'s own rules are left alone: a snoc list is built reversed
by nature. `length` is left alone too (`lengthPlus` allocates nothing).

Only a whole-program compile runs the pass: the added definitions are one per program,
and a per-module compile would add a copy to each module.

## Measured

Off by default, because the gain depends on the program: the compiler's own `prelude`
build, all short lists, is unchanged in instructions (27.97 G off, 28.00 G on: +0.09%) and in time, and
its executable grows 5.5% (the per-call-site clones of `map` are TRMC loops, 225 of them
at 49 lines against 197 `mapAppend` clones at 23); a list-heavy program gains about a
quarter of its time:

| | before | after |
|---|---|---|
| `BenchListAppend` (two 500k lists appended, 40 times) | 6.80 s | 5.18 s (-24%) |
| `BenchListChurn` (map, filter, sum of 300k, 50 times) | 2.35 s | 1.82 s (-23%) |

`Test178ListDivert`: `++`, `map`, `filter` and `mapMaybe` leave no upstream helper in the
IR and TRMC fills the holes under `listdivert`; the output is the same as without it and under RefC.

`verify.sh --directive listdivert` runs the suite with the pass on. Every output matches;
two checks that count IR nodes against a variant their `check.sh` builds without the
global directive (`Test112Numeric`'s comparison-merge counts, `Test13NativeArgChain`'s
`noboolfield` counts) report a difference there, as any global directive that changes the
list code would make them.
