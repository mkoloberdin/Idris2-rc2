# Results whose fields are not read (`Compiler.RC2.DeadFields`)

A call whose result its caller takes apart at once, `case f args of C x y => ...`, may leave some
fields unread: `case isLTE k j of Yes _ => a; No _ => b` reads neither the proof nor the
refutation, `case stats xs of (s, _) => s` reads one half of a pair. `f` still makes them all, and
a recursion like upstream's `isLTE` makes them at every step and has to rebuild its result after
the recursive call, so it is no tail call.

The pass, on the named case trees after inlining (whole program only), gives such a call a copy
of `f` that does not make the fields its `case` does not read:

- A `case` reads field `i` of `C` when it has a branch for `C` whose body mentions that field's
  binder. A constructor it has no branch for goes to the default branch, which reads none of its
  fields.
- The copy is `f`'s body with those fields of every constructor it returns (through `let`s and the
  branches of `case`s) erased, and its tail calls of itself calls of the copy.
- Inside the copy the same rewriting runs, so `case f k j of No c => No (g c); Yes p => Yes (h p)`,
  `f`'s own call taken apart the same way, calls the copy too; its branches now only rebuild what
  they took apart (`No _ => No _`), so the `case` is its scrutinee and the call a tail call.
  Upstream's `isLTE` becomes a loop that allocates nothing until it returns.
- A copy is kept only when it pays for its code: the function is at most 30 nodes, or at most
  300 and the copy is a loop (every call of itself a tail call, none taken apart and rebuilt). A
  copy that does not pay is dropped with every copy made while making it, since one of those may
  call it.
- One copy per function and set of read fields (the order of the branches does not matter), at
  most 500 per program. Only of a function of at least one parameter: a CAF is never copied, so its
  memoized value stays one, which the copies share.

## What is never left out

A field is erased only when computing it can do nothing but produce its value: a local, a
constant, a function of the program (of at least one parameter: naming a CAF evaluates it the first
time, so a reference to one, or to a name the program does not define, is kept), a constructor or
arithmetic of those, a lambda or a delayed value (made, never
run), a `let` or `case` of those. Not a call (it may do IO, through a world token or
`unsafePerformIO`), a world primitive, a `force` (it runs a suspended computation), a `crash`, or a
division (it may fail). When a field cannot be erased, the copy is not made.

The pass erases a field's expression, never a binding: a field that is a local bound to an IO
action (`let y = unsafePerformIO (...) in (x + 1, y)`) is erased, and the action still runs.

Off by default (`--directive deadfields` turns it on): on the two programs measured below it
changed nothing measurable.

`Test183DeadFields`: a `Dec` recursion of the program (upstream's `isLTE` under another name)
gets a copy that makes no proof and calls itself; a pair of which one half is read gets a copy
that does not count; a field made by an IO action is erased and the action still prints. The test turns the pass on (`%cg rc2 deadfields`); the same
output as without the pass. With `myLTE 3000000 3000001` instead, the program built without it
overflows the stack (three million frames that each rebuild a `Yes`); with the
pass it returns in 8 ms.

## Measured

| | instructions | code (`.text`) |
|---|---|---|
| compiler's own `prelude` build, off (default) | 27.971 G | 14.19 MB |
| without the size bound (every copy kept) | 27.990 G | 14.91 MB (+5.0%) |
| with it (`deadfields`) | 27.972 G | 14.19 MB (the same executable) |
| lambda-rogue's tests, off (default) | 21.014 G | 4.11 MB |
| with the size bound (`deadfields`) | 21.012 G | 4.14 MB (+0.7%) |

Without the bound, 45 copies of the compiler's functions were made, and six of them, whole large
functions, were most of the code; the instructions grew a little. With it, 26 small copies are made
and later inlining and `FunDedup` give back the same executable. Neither program has a deep
recursion of this shape; what the pass is for is one like `myLTE` above, which it turns from a
stack overflow into a loop.

## Constant constructors (`Compiler.RC2.ConstFields`)

The same question for the constants `ConstFold` folds a constructor into: a
field no `case` alt of the whole program binds is never read, so a closure
in it only keeps its function alive. Interface dictionaries are the usual
case. In `rc2-norepl` an `Ord` dictionary reaches `Data.SortedMap` as one
constant (`#MkOrd(..)`), and no alt binds its `>`, `<=`, `>=`, `max` or
`min`.

`applyConstFields` runs at the end of `toRCDefs`, after the last
`DeadVars`, which leaves an unread alt field as `_`, and before
`FunDedup`. It collects, for every constructor, the fields some alt binds;
every field of a constructor also returned as a struct (`RRetPack`) counts
as read, and newtypes are left alone. A constant closure in an unread field
of a constant constructor then becomes `[erased]`, and `pruneDeadDefs`
drops the functions nothing names any more. The erased proofs of the
constants are taken again with `ConstFold.allConstLocal`, as in `FunDedup`.

Only closures go: the runtime reads no closure out of a program's data,
while it does read some fields (a list's cells in `fastConcat`). It needs
the whole program, so it does not run in incremental mode. Off with
`--directive noconstfields`.

On `rc2-norepl` (2026-11-24) it drops 167 definitions, and the C goes
from 107.0 MB to 106.9 MB. `Test114Inline/ConstFields` checks that an
`Ord` dictionary's `max` and `min` go.

