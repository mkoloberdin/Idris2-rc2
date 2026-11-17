# `Data.Nat.isLTE` and `lte` in constant time (`Compiler.RC2.NatMagic`)

Upstream's `isLTE` and `lte` (of `Data.Nat`) take their arguments apart one `S` at a time. `Nat`
is an `Integer` at run time, so each step is cheap, but there are `min m n + 1` of them; and
`isLTE` is no tail call: every step rebuilds `Yes (LTESucc prf)` (a `prf + 1`: `LTE` has `Nat`'s
shape, so it is a number too) or composes a refutation. `natToFin k n` calls `isLTE (S k) n`.
Upstream's `natHack` (`Compiler.Opts.Constructor`) replaces `plus`, `minus`, `compareNat` and a
few more functions of `Prelude.Types` by primitives, not these two.

`applyNatMagic` gives the two definitions bodies that compare once, before anything else runs on
the named case trees (whole program and per module):

- `lte m n` is `m <= n` on `Integer`;
- `isLTE m n` is `Yes m` when `m <= n` (the proof `LTESucc (... LTEZero)` is the number of its
  `LTESucc`s, which is `m`), and otherwise `No` of a function that crashes (it is a function to
  `Void`: nothing can call it with a proof).

So `isLT`, `isGTE`, `natToFin` and every other caller are constant time too. `--directive
nonatmagic` keeps upstream's definitions.

## Measured

lambda-rogue's test suite reads its map with `natToFin x 80` and `natToFin y 22` on every tile:

| | instructions | time |
|---|---|---|
| `nonatmagic` | 34.17 G | 3.76 s |
| default | 21.01 G (-38.5%) | 2.37 s |

What is left on top is `Data.Vect.index` (a walk down a list; 43% of the rest).

`Test182NatMagic`: `isLTE` (the size of a `Yes` proof counted at run time), `lte`, `gte`, `lt`,
`natToFin` and `isLT` at the boundaries, the same as with `nonatmagic`; the IR of `isLTE` and `lte`
calls no one.
