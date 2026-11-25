# Shared subtrees

Subtrees of one function that are equal up to the numbering of their
locals become one new function, `rc2_share_<f>_<k>`, which takes their
free locals as arguments, and each copy becomes a call of it
(`Compiler.RC2.ShareSubtrees`).

## Why

The case trees upstream gives rc2 copy code. A function matching nested
patterns falls back to its later clauses in every alt of an outer `case`
that does not match, and the frontend writes that fallback out again in
each of them. `Core.Unify.unifyBothApps` held an 899-line subtree 8 times
and a 307-line one 16 times. Over `rc2-norepl` (2026-11-25), 23% of the
lines of the final IR were a second or later copy of a subtree of at
least five lines in the same definition.

## How

The pass runs right after CAF memoization and before RC, so RC, Loop,
MutualLoop, DualABI and the rest treat a new function like any other,
and a new function of no arguments is no CAF.

1. `FunDedup.dedupFuns` runs first. A lambda in a copied subtree is
   lifted once per copy, under a name of its own, and the copies only
   become equal once those twins are one function. The merge reaches
   further than that: two clones `SpecConstCon` made for dictionaries with
   equal methods become one too (`Test87SpecConstCon` turns this pass off
   for that reason).
2. Every subtree of at least `minNodes` nodes is a candidate, with its
   free locals in the order a walk first reads them. Candidates are
   grouped by size, and the largest go first.
3. Two candidates are equal when `FunDedup.sameUpToLocals` says so: their
   free locals paired in that order, the locals they bind paired as
   `FunDedup`'s equality pairs them. A pairing the order gets wrong only
   loses a share.
4. A class of two or more becomes a function: the body of its first
   member, taking that member's free locals as Boxed parameters. Every
   member is replaced by a call with its own free locals. A candidate
   inside a member is not looked at again.

A copy that reads more than `MaxExtractFunArgs` (20) locals stays too: a
function of more arguments takes them as one array, and every call of it
builds a closure and runs it through the trampoline.

A copy that tail-calls a function of the enclosing function's own cycle
in the tail-call graph (`MutualLoop.tarjanSCCs`) stays where it is: in a
new function, that call would join the cycle, which Loop makes a loop
and the rest leaves to a trampoline. A call of a new function is a leaf
tail call when it is in tail position, so it is a direct C call
(`leaf-tail-calls.md`).

Off with `--directive nosharesubtrees`; it does not run in incremental
mode.

## Measured

`rc2-norepl` (2026-11-25), clang `-O2`, against master:

| | C | `.o` text | binary |
|---|---|---|---|
| master | 101.4 MB | 18.62 MB | 20.13 MB |
| shared subtrees | 88.7 MB (−12.5%) | 17.36 MB (−6.8%) | 18.91 MB (−6.1%) |

154 functions; 23% of the IR lines were repeated subtrees, 16.5% still
are. The pass takes 3.5 s, the merge before it included, and `rc2-norepl`
generating its own C (`--directive nocc`) took 98 s against master's 102 s:
the later passes have less to do. `bench.sh` is within noise.

Tried and dropped:

- Comparing names through the pairing the merge would make
  (`funEquivalence`) instead of merging: no program change besides the
  shares, but 93.4 MB of C, as the merge itself also helps the later
  passes.
- Looking again inside the new functions, and comparing through that
  pairing after the merge: 13 more functions, 10 KB.
- The same at `Emit` with a `goto` to the first copy, kept out of the IR:
  91.1 MB of C, but the IR dump then no longer shows what the C does.

## Not shared yet

Most of what is left is in recursive functions (`TTImp.PartialEval.mkSpecDef`
alone holds 7,651 lines of copies), whose copies tail-call their own cycle.
A function of more than 20 arguments called directly with positional
parameters (task: a wrapper taking the array only for closure calls)
would lift the 20-local limit.

