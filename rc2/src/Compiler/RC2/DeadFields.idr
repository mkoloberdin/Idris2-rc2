||| A function whose result its caller takes apart at once, reading only some fields, gets a copy
||| that does not make the others (`rc2/doc/dead-fields.md`). `case isLTE k j of Yes _ => a; No _ => b`
||| does not need the proof or the refutation: the copy makes `Yes`/`No` of erased fields, its own
||| `case isLTE ...` that only rebuilt them becomes a tail call, and the recursion a loop. A field is
||| left out only when computing it can do nothing but produce the value (a local, a constant, a
||| constructor, a lambda, arithmetic): never a call, a primitive of the world, a `force` or a
||| `crash`, so no IO is lost. Off by default: `--directive deadfields` turns it on.
|||
||| Copyright 2026, Hattori,Hiroki. All rights reserved.
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.DeadFields

import Core.CompileExpr
import Core.Context
import Core.TT

import Data.List
import Data.SortedMap
import Data.String
import Data.Vect

%default covering

||| For each constructor a `case` names, which of its fields the `case` reads. A constructor it does
||| not name goes to its default branch, which reads none.
Reads : Type
Reads = List (Name, List Bool)

record St where
  constructor MkSt
  memo : SortedMap String (Maybe Name)
  added : List (Name, FC, NamedDef)
  count : Nat

||| The most copies made for one program.
maxCopies : Nat
maxCopies = 500

||| A copy pays for its code when the function is at most this many nodes (about as small as the
||| inliner's own bounds: the fields left out are most of the work)...
smallCopy : Nat
smallCopy = 30

||| ...or, up to this many, when the copy is a loop: every call of itself a tail call, no longer
||| taken apart and rebuilt (`isLTE`'s shape; the recursion stops growing the stack).
loopCopy : Nat
loopCopy = 300

subs : NamedCExp -> List NamedCExp
subs (NmLet _ _ v b) = [v, b]
subs (NmApp _ f as) = f :: as
subs (NmLam _ _ b) = [b]
subs (NmCon _ _ _ _ as) = as
subs (NmOp _ _ as) = toList as
subs (NmExtPrim _ _ as) = as
subs (NmForce _ _ t) = [t]
subs (NmDelay _ _ t) = [t]
subs (NmConCase _ sc alts def) = sc :: map (\(MkNConAlt _ _ _ _ b) => b) alts ++ maybe [] pure def
subs (NmConstCase _ sc alts def) = sc :: map (\(MkNConstAlt _ b) => b) alts ++ maybe [] pure def
subs _ = []

mentions : Name -> NamedCExp -> Bool
mentions x (NmLocal _ y) = x == y
mentions x e = any (mentions x) (subs e)

readsOf : List NamedConAlt -> Reads
readsOf = map (\(MkNConAlt n _ _ args b) => (n, map (\a => mentions a b) args))

||| Whether the `case` that `reads` describes reads field `i` of `c`.
reads : Reads -> Name -> Nat -> Bool
reads rs c i = case lookup c rs of
                    Just bs => fromMaybe True (head' (drop i bs))
                    Nothing => False

||| Whether computing `e` can do nothing but produce its value: no call (it may do IO), no world
||| primitive, no `force` (it runs a suspended computation), no `crash`, no division (it may
||| fail). A lambda or a delayed value is only made, never run, so its body does not matter. A
||| global is only a function of at least one parameter: one of none is a CAF, and naming it
||| evaluates it the first time (an `unsafePerformIO` in it, or a crash, would not happen there).
droppable : SortedMap Name NamedDef -> NamedCExp -> Bool
droppable defs = go
  where
    go : NamedCExp -> Bool
    go (NmLocal {}) = True
    go (NmRef _ n) = case lookup n defs of
                          Just (MkNmFun (_ :: _) _) => True
                          _ => False
    go (NmPrimVal {}) = True
    go (NmErased {}) = True
    go (NmLam {}) = True
    go (NmDelay {}) = True
    go (NmCon _ _ _ _ as) = all go as
    go (NmOp _ (Div _) _) = False
    go (NmOp _ (Mod _) _) = False
    go (NmOp _ _ as) = all go (toList as)
    go (NmLet _ _ v b) = go v && go b
    go (NmConstCase _ sc alts def) =
        go sc && all (\(MkNConstAlt _ b) => go b) alts && maybe True go def
    go (NmConCase _ sc alts def) =
        go sc && all (\(MkNConAlt _ _ _ _ b) => go b) alts && maybe True go def
    go _ = False

||| `body` of `f` with the fields a `case` that `rs` describes does not read left out of every
||| constructor it returns, and its tail calls of itself calls of `copy`. `Nothing` when one of those
||| fields cannot be left out; the `Bool` is whether any was.
dropTails : SortedMap Name NamedDef -> Name -> Name -> Reads -> NamedCExp -> Maybe (NamedCExp, Bool)
dropTails defs f copy rs = go
  where
    go : NamedCExp -> Maybe (NamedCExp, Bool)
    goField : Name -> (Nat, NamedCExp) -> Maybe (NamedCExp, Bool)
    goField c (i, a) = if reads rs c i then Just (a, False)
                       else if droppable defs a then Just (NmErased emptyFC, True) else Nothing

    numbered : List NamedCExp -> List (Nat, NamedCExp)
    numbered = go' 0
      where
        go' : Nat -> List NamedCExp -> List (Nat, NamedCExp)
        go' _ [] = []
        go' i (x :: xs) = (i, x) :: go' (S i) xs

    go (NmLet fc x v b) = map (\(b', d) => (NmLet fc x v b', d)) (go b)
    go (NmConCase fc sc alts def) = do
        alts' <- traverse (\(MkNConAlt n ci t as b) => map (\(b', d) => (MkNConAlt n ci t as b', d)) (go b)) alts
        def' <- the (Maybe (Maybe (NamedCExp, Bool))) $ case def of
                     Just d => map Just (go d)
                     Nothing => Just Nothing
        pure (NmConCase fc sc (map fst alts') (map fst def'), any snd alts' || maybe False snd def')
    go (NmConstCase fc sc alts def) = do
        alts' <- traverse (\(MkNConstAlt c b) => map (\(b', d) => (MkNConstAlt c b', d)) (go b)) alts
        def' <- the (Maybe (Maybe (NamedCExp, Bool))) $ case def of
                     Just d => map Just (go d)
                     Nothing => Just Nothing
        pure (NmConstCase fc sc (map fst alts') (map fst def'), any snd alts' || maybe False snd def')
    go (NmCon fc c ci t as) = do
        fs <- traverse (goField c) (numbered as)
        pure (NmCon fc c ci t (map fst fs), any snd fs)
    go (NmApp fc (NmRef rfc g) as) = Just (if g == f then NmApp fc (NmRef rfc copy) as else NmApp fc (NmRef rfc g) as, False)
    go e = Just (e, False)

||| Whether every branch only rebuilds what it took apart, but for erased fields: then the `case` is
||| its scrutinee.
rebuildsOnly : List NamedConAlt -> Bool
rebuildsOnly alts = not (null alts) && all same alts
  where
    sameField : (Name, NamedCExp) -> Bool
    sameField (_, NmErased _) = True
    sameField (x, NmLocal _ y) = x == y
    sameField _ = False

    same : NamedConAlt -> Bool
    same (MkNConAlt n _ _ as (NmCon _ n' _ _ fs)) = n == n' && length as == length fs && all sameField (zip as fs)
    same _ = False

nodes : NamedCExp -> Nat
nodes e = S (sum (map nodes (subs e)))

||| Whether `e` calls `g`, and whether some `case` takes such a call apart.
callsOf : Name -> NamedCExp -> (Bool, Bool)
callsOf g e =
    let here = case e of
                    NmApp _ (NmRef _ h) _ => (h == g, False)
                    NmConCase _ (NmApp _ (NmRef _ h) _) _ _ => (h == g, h == g)
                    _ => (False, False)
        below = map (callsOf g) (subs e)
    in (fst here || any fst below, snd here || any snd below)

keyOf : Name -> Reads -> String
keyOf f rs = show f ++ "|" ++ show (sort (map (\(n, bs) => (show n, bs)) rs))

isOurs : Name -> Bool
isOurs f = isPrefixOf "{rc2_" (show f)

mutual
  ||| `e` with each call whose result is taken apart at once by a `case` that leaves fields unread
  ||| made a call of a copy that does not make them.
  walk : SortedMap Name NamedDef -> St -> NamedCExp -> (NamedCExp, St)
  walk defs st (NmConCase fc sc alts def) =
      let (sc', st1) = walk defs st sc
          (alts', st2) = rewriteAlts defs st1 alts
          (def', st3) = the (Maybe NamedCExp, St) $ case def of
                             Just d => let (d', s) = walk defs st2 d in (Just d', s)
                             Nothing => (Nothing, st2)
      in case sc' of
              NmApp afc (NmRef rfc f) as =>
                  let (copy, st4) = copyFor defs st3 f (readsOf alts')
                  in case copy of
                          Just c => if isNothing def' && rebuildsOnly alts'
                                       then (NmApp afc (NmRef rfc c) as, st4)
                                       else (NmConCase fc (NmApp afc (NmRef rfc c) as) alts' def', st4)
                          Nothing => (NmConCase fc sc' alts' def', st4)
              _ => (NmConCase fc sc' alts' def', st3)
  walk defs st (NmLet fc x v b) =
      let (v', st1) = walk defs st v
          (b', st2) = walk defs st1 b
      in (NmLet fc x v' b', st2)
  walk defs st (NmApp fc f as) =
      let (f', st1) = walk defs st f
          (as', st2) = rewriteList defs st1 as
      in (NmApp fc f' as', st2)
  walk defs st (NmLam fc x b) = let (b', st1) = walk defs st b in (NmLam fc x b', st1)
  walk defs st (NmCon fc n ci t as) = let (as', st1) = rewriteList defs st as in (NmCon fc n ci t as', st1)
  walk defs st (NmOp fc op as) =
      let (as', st1) = rewriteList defs st (toList as)
      in (maybe (NmOp fc op as) (NmOp fc op) (toVect _ as'), st1)
  walk defs st (NmExtPrim fc p as) = let (as', st1) = rewriteList defs st as in (NmExtPrim fc p as', st1)
  walk defs st (NmForce fc lr t) = let (t', st1) = walk defs st t in (NmForce fc lr t', st1)
  walk defs st (NmDelay fc lr t) = let (t', st1) = walk defs st t in (NmDelay fc lr t', st1)
  walk defs st (NmConstCase fc sc alts def) =
      let (sc', st1) = walk defs st sc
          (alts', st2) = foldr (\(MkNConstAlt c b), (acc, s) => let (b', s') = walk defs s b in (MkNConstAlt c b' :: acc, s'))
                               (the (List NamedConstAlt) [], st1) alts
          (def', st3) = the (Maybe NamedCExp, St) $ case def of
                             Just d => let (d', s) = walk defs st2 d in (Just d', s)
                             Nothing => (Nothing, st2)
      in (NmConstCase fc sc' alts' def', st3)
  walk _ st e = (e, st)

  rewriteList : SortedMap Name NamedDef -> St -> List NamedCExp -> (List NamedCExp, St)
  rewriteList defs st es = foldr (\e, (acc, s) => let (e', s') = walk defs s e in (e' :: acc, s')) ([], st) es

  rewriteAlts : SortedMap Name NamedDef -> St -> List NamedConAlt -> (List NamedConAlt, St)
  rewriteAlts defs st alts =
      foldr (\(MkNConAlt n ci t as b), (acc, s) => let (b', s') = walk defs s b in (MkNConAlt n ci t as b' :: acc, s'))
            ([], st) alts

  ||| The copy of `f` for a `case` that `rs` describes, made the first time it is asked for. The
  ||| name is recorded before the body is made, so the copy's own calls of `f` taken apart the same
  ||| way call the copy.
  copyFor : SortedMap Name NamedDef -> St -> Name -> Reads -> (Maybe Name, St)
  copyFor defs st f rs =
      let key = keyOf f rs in
      case lookup key st.memo of
           Just r => (r, st)
           Nothing =>
               case lookup f defs of
                    Just (MkNmFun params@(_ :: _) body) =>
                        if isOurs f || st.count >= maxCopies then (Nothing, { memo $= insert key Nothing } st) else
                        let copy = MN ("rc2_dropf_" ++ show st.count) 0
                            st1 = { memo $= insert key (Just copy), count $= S } st
                        in case dropTails defs f copy rs body of
                                Just (body', True) =>
                                    let (body'', st2) = walk defs st1 body'
                                        size = nodes body
                                        (recurs, takesApart) = callsOf copy body''
                                        pays = size <= smallCopy || (size <= loopCopy && recurs && not takesApart)
                                    in if pays
                                          then (Just copy, { added $= ((copy, emptyFC, MkNmFun params body'') ::) } st2)
                                          -- dropped with every copy made while making it: one of them may call
                                          -- this one, whose name was recorded first
                                          else (Nothing, { memo := insert key Nothing st.memo, count := st2.count } st)
                                _ => (Nothing, { memo $= insert key Nothing } st1)
                    _ => (Nothing, { memo $= insert key Nothing } st)

||| Every definition and `main` rewritten, and the copies they call added.
export
applyDeadFields : Maybe NamedCExp -> List (Name, FC, NamedDef) -> (Maybe NamedCExp, List (Name, FC, NamedDef))
applyDeadFields main defs =
    let table = SortedMap.fromList (map (\(n, _, d) => (n, d)) defs)
        st0 = MkSt SortedMap.empty [] 0
        (defs', st1) = foldr (\(n, fc, d), (acc, s) => case d of
                                  MkNmFun args b => let (b', s') = walk table s b in ((n, fc, MkNmFun args b') :: acc, s')
                                  other => ((n, fc, other) :: acc, s))
                             (the (List (Name, FC, NamedDef)) [], st0) defs
        (main', st2) = the (Maybe NamedCExp, St) $ case main of
                            Just m => let (m', s) = walk table st1 m in (Just m', s)
                            Nothing => (Nothing, st1)
    in (main', defs' ++ reverse st2.added)
