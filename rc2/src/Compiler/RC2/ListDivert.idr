||| Replaces the tail-recursive list functions that upstream's `%transform` rules put
||| in (`tailRecAppend`, `mapTR`, `filterTR`, `mapMaybeTR`: two passes and an
||| intermediate list each) by naive definitions of rc2's own, which `Compiler.RC2.Trmc`
||| turns into one loop. Off by default: `--directive listdivert` turns it on. See
||| `rc2/doc/list-divert.md`.
|||
||| Copyright 2026, Hattori,Hiroki. All rights reserved.
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.ListDivert

import Core.CompileExpr
import Core.Context
import Core.TT

import Data.List
import Data.SortedSet
import Data.Vect

%default covering

||| The functions rc2 defines in place of upstream's.
data Diverted = DAppend | DMap | DFilter | DMapMaybe

divertedName : Diverted -> Name
divertedName DAppend = MN "rc2_append" 0
divertedName DMap = MN "rc2_map" 0
divertedName DFilter = MN "rc2_filter" 0
divertedName DMapMaybe = MN "rc2_mapMaybe" 0

divertedKey : Diverted -> Nat
divertedKey DAppend = 0
divertedKey DMap = 1
divertedKey DFilter = 2
divertedKey DMapMaybe = 3

allDiverted : List Diverted
allDiverted = [DAppend, DMap, DFilter, DMapMaybe]

isFun : String -> Name -> Bool
isFun s n = show n == s

||| `[]` (also `Lin`, the same constructor).
isNil : NamedCExp -> Bool
isNil (NmCon _ _ NIL _ []) = True
isNil _ = False

||| The call of a diverted function the upstream call `f args` is, if any:
||| `reverseOnto ys (reverseOnto [] xs)` is `tailRecAppend xs ys` inlined;
||| `mapAppend [] f xs` is `mapTR f xs`, and the same for `filter` and `mapMaybe`.
divert : FC -> Name -> List NamedCExp -> Maybe (Diverted, List NamedCExp)
divert fc f args = case args of
    -- `tailRecAppend xs ys`, or what the inliner leaves of it: `reverseOnto ys (reverseOnto [] xs)`
    -- or `reverseOnto ys (reverse xs)`. One alternative for every two-argument call: a `case`
    -- takes the first alternative that matches, so these cannot be three.
    [a, b] =>
        if isFun "Prelude.Types.List.tailRecAppend" f then Just (DAppend, [a, b])
        else if isFun "Prelude.Types.List.reverseOnto" f
           then case b of
                     NmApp _ (NmRef _ g) [z, xs] =>
                         if isFun "Prelude.Types.List.reverseOnto" g && isNil z then Just (DAppend, [xs, a]) else Nothing
                     NmApp _ (NmRef _ g) [xs] =>
                         if isFun "Prelude.Types.List.reverse" g then Just (DAppend, [xs, a]) else Nothing
                     _ => Nothing
           else Nothing
    [z, g, xs] =>
        if not (isNil z) then Nothing
        else if isFun "Prelude.Types.List.mapAppend" f then Just (DMap, [g, xs])
        else if isFun "Prelude.Types.List.filterAppend" f then Just (DFilter, [g, xs])
        else if isFun "Prelude.Types.List.mapMaybeAppend" f then Just (DMapMaybe, [g, xs])
        else Nothing
    _ => Nothing

||| `e` with every upstream call made a call of the diverted function, and the set
||| of those used.
divertCalls : NamedCExp -> (NamedCExp, SortedSet Nat)
divertCalls = go
  where
   mutual
    goList : List NamedCExp -> (List NamedCExp, SortedSet Nat)
    goList es = foldr (\e, (acc, s) => let (e', s') = go e in (e' :: acc, union s s')) (the (List NamedCExp) [], SortedSet.empty) es

    go : NamedCExp -> (NamedCExp, SortedSet Nat)
    go (NmApp fc (NmRef rfc f) args) =
        let (args', s) = goList args
        in case divert fc f args' of
                Just (d, dargs) => (NmApp fc (NmRef rfc (divertedName d)) dargs, insert (divertedKey d) s)
                Nothing => (NmApp fc (NmRef rfc f) args', s)
    go (NmApp fc g args) = let (g', s1) = go g; (args', s2) = goList args in (NmApp fc g' args', union s1 s2)
    go (NmLam fc x b) = let (b', s) = go b in (NmLam fc x b', s)
    go (NmLet fc x v b) = let (v', s1) = go v; (b', s2) = go b in (NmLet fc x v' b', union s1 s2)
    go (NmCon fc n ci t args) = let (args', s) = goList args in (NmCon fc n ci t args', s)
    go (NmOp fc op args) =
        let (args', s) = goList (toList args)
        in (maybe (NmOp fc op args) (NmOp fc op) (toVectExact args'), s)
    go (NmExtPrim fc p args) = let (args', s) = goList args in (NmExtPrim fc p args', s)
    go (NmForce fc lr t) = let (t', s) = go t in (NmForce fc lr t', s)
    go (NmDelay fc lr t) = let (t', s) = go t in (NmDelay fc lr t', s)
    go (NmConCase fc sc alts def) =
        let (sc', s0) = go sc
            (alts', s1) = foldr (\(MkNConAlt n ci t as b), (acc, s) => let (b', s') = go b in (MkNConAlt n ci t as b' :: acc, union s s')) (the (List NamedConAlt) [], s0) alts
            (def', s2) = the (Maybe NamedCExp, SortedSet Nat) $ case def of
                              Just d => let (d', s') = go d in (Just d', union s1 s')
                              Nothing => (Nothing, s1)
        in (NmConCase fc sc' alts' def', s2)
    go (NmConstCase fc sc alts def) =
        let (sc', s0) = go sc
            (alts', s1) = foldr (\(MkNConstAlt c b), (acc, s) => let (b', s') = go b in (MkNConstAlt c b' :: acc, union s s')) (the (List NamedConstAlt) [], s0) alts
            (def', s2) = the (Maybe NamedCExp, SortedSet Nat) $ case def of
                              Just d => let (d', s') = go d in (Just d', union s1 s')
                              Nothing => (Nothing, s1)
        in (NmConstCase fc sc' alts' def', s2)
    go e = (e, SortedSet.empty)

    toVectExact : {n : Nat} -> List NamedCExp -> Maybe (Vect n NamedCExp)
    toVectExact {n} xs = toVect n xs

-- The naive definitions, in the shape `Compiler.RC2.Trmc` turns into a loop: the
-- recursive call is the last field of the `::` it builds.
builtin : String -> Name
builtin s = NS (mkNamespace "_builtin") (UN (Basic s))

local : String -> Name
local s = MN s 0

var : String -> NamedCExp
var s = NmLocal emptyFC (local s)

nil : NamedCExp
nil = NmCon emptyFC (builtin "NIL") NIL (Just 0) []

cons : NamedCExp -> NamedCExp -> NamedCExp
cons x xs = NmCon emptyFC (builtin "CONS") CONS (Just 1) [x, xs]

call : Name -> List NamedCExp -> NamedCExp
call n args = NmApp emptyFC (NmRef emptyFC n) args

||| `case xs of [] => onNil; x :: rest => onCons`, `x` and `rest` the locals named.
listCase : NamedCExp -> NamedCExp -> NamedCExp -> NamedCExp
listCase xs onNil onCons =
    NmConCase emptyFC xs
        [ MkNConAlt (builtin "NIL") NIL (Just 0) [] onNil
        , MkNConAlt (builtin "CONS") CONS (Just 1) [local "x", local "rest"] onCons ]
        Nothing

definition : Diverted -> NamedDef
definition DAppend =
    MkNmFun [local "xs", local "ys"] $
        listCase (var "xs") (var "ys") (cons (var "x") (call (divertedName DAppend) [var "rest", var "ys"]))
definition DMap =
    MkNmFun [local "f", local "xs"] $
        listCase (var "xs") nil (cons (NmApp emptyFC (var "f") [var "x"]) (call (divertedName DMap) [var "f", var "rest"]))
definition DFilter =
    MkNmFun [local "p", local "xs"] $
        listCase (var "xs") nil $
            NmConstCase emptyFC (NmApp emptyFC (var "p") [var "x"])
                -- a Bool is a `B8` constant (upstream's `Compiler.Opts.Constructor.enumTag`)
                [ MkNConstAlt (B8 1) (cons (var "x") (call (divertedName DFilter) [var "p", var "rest"]))
                , MkNConstAlt (B8 0) (call (divertedName DFilter) [var "p", var "rest"]) ]
                Nothing
definition DMapMaybe =
    MkNmFun [local "f", local "xs"] $
        listCase (var "xs") nil $
            NmConCase emptyFC (NmApp emptyFC (var "f") [var "x"])
                [ MkNConAlt (builtin "JUST") JUST (Just 1) [local "v"] (cons (var "v") (call (divertedName DMapMaybe) [var "f", var "rest"]))
                , MkNConAlt (builtin "NOTHING") NOTHING (Just 0) [] (call (divertedName DMapMaybe) [var "f", var "rest"]) ]
                Nothing

||| Every program definition rewritten, and the diverted functions that are called
||| added (each calls itself, so its own body needs no rewriting).
export
applyListDivert : Maybe NamedCExp -> List (Name, FC, NamedDef) -> (Maybe NamedCExp, List (Name, FC, NamedDef))
applyListDivert main defs =
    let (main', s0) = the (Maybe NamedCExp, SortedSet Nat) $ case main of
                           Just m => let (m', s) = divertCalls m in (Just m', s)
                           Nothing => (Nothing, SortedSet.empty)
        (defs', used) = foldr (\(n, fc, d), (acc, s) => let (d', s') = rewriteDef d in ((n, fc, d') :: acc, union s s')) (the (List (Name, FC, NamedDef)) [], s0) defs
        added = [ (divertedName d, emptyFC, definition d) | d <- allDiverted, contains (divertedKey d) used ]
    in (main', defs' ++ added)
  where
    rewriteDef : NamedDef -> (NamedDef, SortedSet Nat)
    rewriteDef (MkNmFun args b) = let (b', s) = divertCalls b in (MkNmFun args b', s)
    rewriteDef (MkNmError b) = let (b', s) = divertCalls b in (MkNmError b', s)
    rewriteDef d = (d, SortedSet.empty)
