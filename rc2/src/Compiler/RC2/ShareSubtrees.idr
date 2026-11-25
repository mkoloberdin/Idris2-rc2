||| Subtrees of one function that are equal up to the numbering of their
||| locals become one new function, called from where each copy was
||| (`rc2/doc/shared-subtrees.md`). Runs before RC, so every later pass
||| treats the new function like any other. Disable with
||| `--directive nosharesubtrees`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.ShareSubtrees

import Compiler.RC2.Emit.Util
import Compiler.RC2.FunDedup
import Compiler.RC2.MutualLoop
import Compiler.RC2.RCExp

import Core.FC
import Core.TT
import Core.Name

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default covering

||| The smallest subtree worth a function of its own, in nodes.
minNodes : Nat
minNodes = 24

-- A subtree, by the child indexes leading to it from the body, last first.
record Cand where
  constructor MkCand
  size : Nat
  path : List Nat
  expr : RCExp
  free : Lazy (List LocalId)

-- The locals `e` reads and does not bind, in the order a walk first reads them.
freeOrder : RCExp -> List LocalId
freeOrder e =
    let free = SortedSet.fromList (mapMaybe idOf (Prelude.toList (freeLocalsR e)))
        (walked, seen) = foldl (step free) ([], empty) (mapMaybe idOf (reads [e]))
    in reverse walked ++ filter (\i => not (contains i seen)) (Prelude.toList free)
  where
    reads : List RCExp -> List RCLocal
    reads [] = []
    reads (x :: xs) = directReads x ++ reads (children x ++ xs)

    step : SortedSet LocalId -> (List LocalId, SortedSet LocalId) -> LocalId -> (List LocalId, SortedSet LocalId)
    step free (acc, seen) i =
        if contains i free && not (contains i seen) then (i :: acc, insert i seen) else (acc, seen)

-- The size of `e`, and every subtree of it of at least `minNodes` nodes.
collect : List Nat -> RCExp -> (Nat, List Cand)
collect path e =
    let rs = zipWith (\i, k => collect (i :: path) k) [0 .. length (children e)] (children e)
        size = S (sum (map fst rs))
        below = concatMap snd rs
    in (size, if size >= minNodes then MkCand size path e (freeOrder e) :: below else below)

-- Whether `p` (last index first) lies in a subtree at `q`.
inside : List Nat -> List Nat -> Bool
inside p q = isSuffixOf q p

-- `e` with the subtree at each path (first index first) replaced.
replaceAt : List (List Nat, RCExp) -> RCExp -> RCExp
replaceAt [] e = e
replaceAt reps e = case find (null . fst) reps of
    Just (_, r) => r
    Nothing =>
        let ks = children e
        in withChildren e (zipWith (\i, k => replaceAt (mapMaybe (under i) reps) k) [0 .. length ks] ks)
  where
    under : Nat -> (List Nat, RCExp) -> Maybe (List Nat, RCExp)
    under i (j :: rest, r) = if j == i then Just (rest, r) else Nothing
    under _ ([], _) = Nothing

||| The functions of the program, by the components of its tail-call graph.
sccOf : List (Name, RCDef) -> SortedMap Name (SortedSet Name)
sccOf defs =
    let graph = SortedMap.fromList (mapMaybe (\(n, d) => case d of
                                                 MkRCFun _ _ _ body => Just (n, tailCallTargets body)
                                                 _ => Nothing) defs)
    in foldl (\m, comp => let s = SortedSet.fromList comp
                          in foldl (\m', n => insert n s m') m comp) empty (tarjanSCCs graph)

-- One function's body with its repeated subtrees called instead, and the
-- functions they became.
shareIn : Name -> SortedSet Name -> RCExp -> (RCExp, List (Name, RCDef))
shareIn f scc body =
    let (_, cands) = collect [] body
        bySize = foldl (\m, c => insertWith (++) c.size [c] m) (the (SortedMap Nat (List Cand)) empty) cands
        -- largest first, and only sizes that occur more than once
        groups = filter (\g => length g >= 2) (map snd (reverse (SortedMap.toList bySize)))
        (reps, defs, _, _) = foldl doSize ([], [], [], Z) groups
    in (replaceAt (map (\(p, r) => (reverse p, r)) reps) body, defs)
  where
    -- A copy holding a tail call into this function's own cycle would turn
    -- the loop it makes into a call. One that reads no local makes a
    -- function of no arguments, which is no CAF: memoization has run.
    -- One of more than `MaxExtractFunArgs` arguments would be called through
    -- a closure and the trampoline.
    eligible : Cand -> Bool
    eligible c = length c.free <= MaxExtractFunArgs && null (filter (\n => contains n scc) (Prelude.toList (tailCallTargets c.expr)))

    classes : List Cand -> List (List Cand)
    classes [] = []
    classes (c :: cs) =
        let fc = c.free
            same = \d => length d.free == length fc && sameUpToLocals fc d.free c.expr d.expr
            (here, rest) = partition same cs
        in (c :: here) :: classes rest

    doSize : (List (List Nat, RCExp), List (Name, RCDef), List (List Nat), Nat) -> List Cand
          -> (List (List Nat, RCExp), List (Name, RCDef), List (List Nat), Nat)
    doSize st group =
        let (_, _, covered, _) = st
            here = filter (\c => not (any (inside c.path) covered) && eligible c) group
        in foldl one st (filter (\cl => length cl >= 2) (classes here))
      where
        one : (List (List Nat, RCExp), List (Name, RCDef), List (List Nat), Nat) -> List Cand
           -> (List (List Nat, RCExp), List (Name, RCDef), List (List Nat), Nat)
        one (reps, defs, covered, k) cl@(c :: _) =
            let name = MN ("rc2_share_" ++ cName f) (cast k)
                params = c.free
                call = \d => RAppName emptyFC Nothing name (map RCLoc d.free)
            in ( map (\d => (d.path, call d)) cl ++ reps
               , (name, MkRCFun (map (\p => (p, RBoxed)) params) RBoxed False c.expr) :: defs
               , map path cl ++ covered
               , S k )
        one st [] = st

||| Every function's repeated subtrees made calls of new functions
||| (rc2/doc/shared-subtrees.md).
export
applyShareSubtrees : List (Name, RCDef) -> List (Name, RCDef)
applyShareSubtrees defs =
    let sccs = sccOf defs
    in concatMap (\(n, d) => case d of
          MkRCFun args r w body =>
              let (body', new) = shareIn n (fromMaybe (singleton n) (lookup n sccs)) body
              in (n, MkRCFun args r w body') :: new
          _ => [(n, d)]) defs
