||| Which locals an `RCExp` reads natively: the `PrimType` a parameter is consistently used at (`nativeArgType*`) and the supporting operand analysis.
||| Read-only; shared by `Loop`, `LateInline`, `DualABI` and `ConAltNative`.  See `rc2/doc/native-type-inference.md`.
|||
||| Copyright 2026, Hattori,Hiroki. All rights reserved.
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.NativeUse

import Compiler.RC2.RCExp
import Compiler.RC2.Types

import Core.TT

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

------------------------------------------------------------------------
-- Deciding which top-level parameters are worth a native shadow (see
-- this module's own header note), and rewriting the ownership
-- bookkeeping `Compiler.RC2.RC`'s `annotate` left behind for one once
-- it's promoted.

||| `SortedMap.mergeWith union` -- named once for readability at every
||| multi-id merge point below (see "Batched, multi-id native-type
||| analysis" further down for why these exist).
export
unionMaps : Ord ty => SortedMap Int (SortedSet ty) -> SortedMap Int (SortedSet ty) -> SortedMap Int (SortedSet ty)
unionMaps = SortedMap.mergeWith union

export
concatMaps : Ord ty => List (SortedMap Int (SortedSet ty)) -> SortedMap Int (SortedSet ty)
concatMaps = foldl unionMaps empty

||| If `a` is one of `tracked`'s own ids, record that it was read at
||| native type `ty` here (unioned with whatever's already on file for
||| it); otherwise leave `acc` unchanged.
export
addTracked : Ord ty => SortedSet Int -> RCLocal -> ty -> SortedMap Int (SortedSet ty) -> SortedMap Int (SortedSet ty)
addTracked tracked (RCLoc i) ty acc = if contains i tracked then SortedMap.insertWith union i (SortedSet.singleton ty) acc else acc
addTracked _ _ _ acc = acc

||| A slot's own already-decided native `PrimType`, if it has one --
||| shared by every "is this position read natively" check over an
||| `RLoop`'s own `loopParams`.
export
nativeSlotTy : Rep -> Maybe PrimType
nativeSlotTy (RNative (TPrim ty)) = Just ty
nativeSlotTy (RInlineNative (TPrim ty)) = Just ty
nativeSlotTy _ = Nothing

||| The single native `PrimType` every alt of a constant-`case` matches
||| its scrutinee against, or `Nothing` when they disagree or the type
||| isn't native-eligible at all. `Types.litRep` already answers
||| `Nothing` for `BI` and `Str`, so a GMP `Integer` or `String`
||| scrutinee keeps its Boxed read -- the only two shapes
||| `Compiler.RC2.Emit`'s own `emitConstCaseInto` has no native
||| rendering for (it has rendered every other scrutinee per its own
||| `Rep` since this module's native-shadow promotion needed it).
export
constAltsNativeType : List RConstAlt -> Maybe PrimType
constAltsNativeType [] = Nothing
constAltsNativeType (MkRConstAlt c _ :: rest) =
    case litRep c of
         Nothing => Nothing
         Just ty => if allMatch ty rest then Just ty else Nothing
  where
    -- `MkRConstAlt`'s own second field is an `RCExp`, deliberately
    -- unexamined here: only the matched constant decides the type.
    allMatch : PrimType -> List RConstAlt -> Bool
    allMatch _ [] = True
    allMatch ty (MkRConstAlt c' _ :: xs) = litRep c' == Just ty && allMatch ty xs

||| The single-type verdict `nativeArgType`/`callArgOrOpNativeTy`
||| themselves return: `Just ty` only if `m`'s own entry for `p` is a
||| *consistent* singleton (every native-context read of `p` agreed on
||| the same type); `Nothing` for no reads at all, or for conflicting
||| ones (conservatively left `RBoxed` rather than guessing) -- same
||| rule those two already applied, just factored out so the batched
||| entry points below (and their singleton-callers) share it.
export
singleTypeFrom : SortedMap Int (SortedSet PrimType) -> Int -> Maybe PrimType
singleTypeFrom m p = case lookup p m of
                           Nothing => Nothing
                           Just tys => case Prelude.toList tys of
                                            [ty] => Just ty
                                            _ => Nothing

||| The C expression type a specific operand position of `op` needs,
||| given the enclosing `RLet`'s own native `ty` -- `p`'s contribution
||| to `nativeArgTypes` at every position it fills.
opNativeUses : (p : Int) -> PrimType -> PrimFn arity -> Vect arity RCLocal -> SortedSet PrimType
opNativeUses p ty op args =
    fromList $ mapMaybe (\a => if a == RCLoc p then Just (opArgTyFor ty op) else Nothing) (toList args)

||| Multi-id version of `opNativeUses`: every one of `tracked`'s own
||| contribution to the native-operand-type map, from this one `op`'s
||| own argument positions, in one pass instead of one call per id.
opNativeUsesAll : SortedSet Int -> PrimType -> PrimFn arity -> Vect arity RCLocal -> SortedMap Int (SortedSet PrimType)
opNativeUsesAll tracked ty op args = foldr (\a, acc => addTracked tracked a (opArgTyFor ty op) acc) empty (toList args)

||| `p`'s native-operand contribution at native type `ty` (an `RLet`'s decided
||| `Rep`) if `value` is the `ROp` bound by that let, seeing through leading
||| `RDup`/`RDrop`/`RFree`/`RReleaseReuse` and nested `RLet` bodies. A bare `ROp`
||| with no enclosing native `RLet` is deliberately not counted: it may still
||| render Boxed (leak in Test110Loop/SelfTailLoop.idr).
||| See `rc2/doc/loop-conversion.md`'s "Known limitation".
opNativeUsesThrough : (p : Int) -> PrimType -> RCExp -> SortedSet PrimType
opNativeUsesThrough p ty (ROp _ _ op args _) = opNativeUses p ty op args
opNativeUsesThrough p ty (RDup _ _ _ cont) = opNativeUsesThrough p ty cont
opNativeUsesThrough p ty (RDrop _ _ cont) = opNativeUsesThrough p ty cont
opNativeUsesThrough p ty (RFree _ _ cont) = opNativeUsesThrough p ty cont
opNativeUsesThrough p ty (RReleaseReuse _ _ cont) = opNativeUsesThrough p ty cont
opNativeUsesThrough p ty (RLet _ _ _ _ body) = opNativeUsesThrough p ty body
opNativeUsesThrough _ _ _ = empty

||| Multi-id version of `opNativeUsesThrough`.
opNativeUsesThroughAll : SortedSet Int -> PrimType -> RCExp -> SortedMap Int (SortedSet PrimType)
opNativeUsesThroughAll tracked ty (ROp _ _ op args _) = opNativeUsesAll tracked ty op args
opNativeUsesThroughAll tracked ty (RDup _ _ _ cont) = opNativeUsesThroughAll tracked ty cont
opNativeUsesThroughAll tracked ty (RDrop _ _ cont) = opNativeUsesThroughAll tracked ty cont
opNativeUsesThroughAll tracked ty (RFree _ _ cont) = opNativeUsesThroughAll tracked ty cont
opNativeUsesThroughAll tracked ty (RReleaseReuse _ _ cont) = opNativeUsesThroughAll tracked ty cont
opNativeUsesThroughAll tracked ty (RLet _ _ _ _ body) = opNativeUsesThroughAll tracked ty body
opNativeUsesThroughAll _ _ _ = empty

||| Every native `PrimType` at which top-level parameter `p` is read as an operand
||| of a native-result `ROp` or a fused `RCmpCase`; the only reads Emit does
||| natively. Walks the whole tree. A bare `ROp` is not counted (see
||| `opNativeUsesThrough`). See `rc2/doc/loop-conversion.md`'s "Native-shadow promotion".
export
nativeArgTypes : (p : Int) -> RCExp -> SortedSet PrimType
nativeArgTypes p (RLet _ _ rep value body) =
    let fromOp = case rep of
             RNative (TPrim ty) => opNativeUsesThrough p ty value
             RInlineNative (TPrim ty) => opNativeUsesThrough p ty value
             _ => empty
    in fromOp `union` (nativeArgTypes p value `union` nativeArgTypes p body)
nativeArgTypes p (RCmpCase _ op args _ t f) =
    let fromArgs = fromList $ mapMaybe (\a => if a == RCLoc p && nativeEligible (cmpOpTy op) then Just (cmpOpTy op) else Nothing) (toList args)
    in fromArgs `union` (nativeArgTypes p t `union` nativeArgTypes p f)
nativeArgTypes p (RDup _ _ _ cont) = nativeArgTypes p cont
nativeArgTypes p (RDrop _ _ cont) = nativeArgTypes p cont
nativeArgTypes p (RFree _ _ cont) = nativeArgTypes p cont
nativeArgTypes p (RReleaseReuse _ _ cont) = nativeArgTypes p cont
nativeArgTypes p (RReuseOffer _ _ _ _ cont) = nativeArgTypes p cont
nativeArgTypes p (RConCase _ _ alts mDef) =
    concat (map (\(MkRConAlt _ _ _ _ body) => nativeArgTypes p body) alts)
      `union` maybe empty (nativeArgTypes p) mDef
-- The scrutinee position counts too: `Compiler.RC2.Emit`'s own
-- `emitConstCaseInto` renders it per its own `Rep`, so dispatching on a
-- native local needs no unboxing at all -- exactly the "countdown's own
-- `0` check" this pass's own native-shadow promotion was always meant
-- to cover (see `applyLoop`), and the shape a `Bool`-returning worker's
-- result lands in. `RConCase`'s own scrutinee is a constructor and is
-- correctly left out.
nativeArgTypes p (RConstCase _ sc alts mDef) =
    let fromSc = if sc == RCLoc p
                    then maybe empty SortedSet.singleton (constAltsNativeType alts)
                    else empty
    in fromSc
         `union` (concat (map (\(MkRConstAlt _ body) => nativeArgTypes p body) alts)
                    `union` maybe empty (nativeArgTypes p) mDef)
-- `RLoop` itself carries no native-context operand reads directly
-- (`loopParams`/`initial`/`prologueDrop` are metadata, not operations
-- to scan), but its own `body` can -- once genuinely reachable here
-- (`Compiler.RC2.LateInline`, running after this pass, can splice a
-- loop-converted callee into a not-yet-DualABI-processed caller;
-- `Compiler.RC2.DualABI`'s own `paramEligibility` reuses this exact
-- function on such a body when no loop sits behind a bare `RLet`
-- prefix -- see rc2/doc/inlining.md's "Known limitation" section for
-- the gap this closes).
-- `initial` is not just metadata after all: `Emit`'s own
-- `declareLoopParam` renders each entry through `rcVarToNativeC` keyed
-- on *that slot's* own `Rep`, so supplying an already-`RNative` slot is
-- a genuine native read of `p` -- the `RLoopContinue` analogue one
-- iteration earlier. Unreachable from `Compiler.RC2.Loop`'s own
-- param-shadow decision (which runs before its own `RLoop` exists, and
-- there is only ever one per function); this is for
-- `Compiler.RC2.DualABI`'s and `Compiler.RC2.LateInline`'s own later
-- reuse, where the loop is already built.
nativeArgTypes p (RLoop _ loopParams initial _ body) =
    let fromInitial = fromList $ mapMaybe (\((_, slotRep), a) =>
                          if a == RCLoc p then nativeSlotTy slotRep else Nothing)
                          (zip loopParams initial)
    in fromInitial `union` nativeArgTypes p body
-- Every other shape (RV, RAppName, RUnderApp, RApp, RCon, a bare ROp,
-- RExtPrim, RPrimVal, RErased, RCrash, RLoopContinue): no native-
-- context operand reads live directly in these (a bare ROp
-- deliberately excepted -- see nativeArgTypes's own doc comment), and
-- none hold a further RCExp to recurse into beyond what's covered
-- above.
nativeArgTypes _ _ = empty

-- Batched analysis: `nativeArgType` and `callArgOrOpNativeTy` answer for one id
-- and walk the whole body each time, so asking once per parameter costs
-- O(parameters x body size); the `...For`/`...All` forms answer for a set of
-- ids in one walk. See `rc2/doc/loop-conversion.md`.

||| Multi-id version of `nativeArgTypes`: every one of `tracked`'s own
||| native-operand-type set, computed together in *one* walk of `body`
||| instead of one full walk per id. See "Batched, multi-id native-type
||| analysis" below for why this exists.
export
nativeArgTypesFor : SortedSet Int -> RCExp -> SortedMap Int (SortedSet PrimType)
nativeArgTypesFor tracked (RLet _ _ rep value body) =
    let fromOp = case rep of
             RNative (TPrim ty) => opNativeUsesThroughAll tracked ty value
             RInlineNative (TPrim ty) => opNativeUsesThroughAll tracked ty value
             _ => empty
    in fromOp `unionMaps` (nativeArgTypesFor tracked value `unionMaps` nativeArgTypesFor tracked body)
nativeArgTypesFor tracked (RCmpCase _ op args _ t f) =
    let fromArgs = if nativeEligible (cmpOpTy op)
                      then foldr (\a, acc => addTracked tracked a (cmpOpTy op) acc) empty (toList args)
                      else empty
    in fromArgs `unionMaps` (nativeArgTypesFor tracked t `unionMaps` nativeArgTypesFor tracked f)
nativeArgTypesFor tracked (RDup _ _ _ cont) = nativeArgTypesFor tracked cont
nativeArgTypesFor tracked (RDrop _ _ cont) = nativeArgTypesFor tracked cont
nativeArgTypesFor tracked (RFree _ _ cont) = nativeArgTypesFor tracked cont
nativeArgTypesFor tracked (RReleaseReuse _ _ cont) = nativeArgTypesFor tracked cont
nativeArgTypesFor tracked (RReuseOffer _ _ _ _ cont) = nativeArgTypesFor tracked cont
nativeArgTypesFor tracked (RConCase _ _ alts mDef) =
    concatMaps (map (\(MkRConAlt _ _ _ _ body) => nativeArgTypesFor tracked body) alts)
      `unionMaps` maybe empty (nativeArgTypesFor tracked) mDef
-- See `nativeArgTypes`'s own `RConstCase` case for why the scrutinee
-- position counts.
nativeArgTypesFor tracked (RConstCase _ sc alts mDef) =
    let fromSc = maybe empty (\ty => addTracked tracked sc ty empty) (constAltsNativeType alts)
    in fromSc
         `unionMaps` (concatMaps (map (\(MkRConstAlt _ body) => nativeArgTypesFor tracked body) alts)
                        `unionMaps` maybe empty (nativeArgTypesFor tracked) mDef)
-- See `nativeArgTypes`'s own `RLoop` case just above for why this is
-- reachable now, and why recursing into `body` (ignoring `loopParams`/
-- `initial`/`prologueDrop`, metadata rather than operations) suffices.
-- See `nativeArgTypes`'s own `RLoop` case just above for why `initial`
-- counts as a native read of an already-`RNative` slot.
nativeArgTypesFor tracked (RLoop _ loopParams initial _ body) =
    let fromInitial : SortedMap Int (SortedSet PrimType) =
            foldr (\((_, slotRep), a), acc =>
                       maybe acc (\ty => addTracked tracked a ty acc) (nativeSlotTy slotRep))
                  (the (SortedMap Int (SortedSet PrimType)) SortedMap.empty)
                  (zip loopParams initial)
    in fromInitial `unionMaps` nativeArgTypesFor tracked body
nativeArgTypesFor _ _ = empty

||| What the declared types show (`--directive strictnative`, rc2/doc/native-type-inference.md's "The strict mode"):
||| what each parameter id, function result and constructor field may be held as. One not listed is not shown.
public export
record Strict where
  constructor MkStrict
  params : SortedMap Int (List NativeTy)
  returns : SortedMap Name (List NativeTy)
  cons : SortedMap Name (List (List NativeTy))

||| Whether the function `n`'s declared result shows that it may be held as `ty`; always, without the mode.
export
returnShown : Maybe Strict -> Name -> NativeTy -> Bool
returnShown strict n ty = maybe True (\s => maybe False (elem ty) (lookup n s.returns)) strict

||| `strict` narrowed to the fields `args` of the constructor `con`.
export
fieldStrict : Maybe Strict -> Name -> List Int -> Maybe Strict
fieldStrict strict con args =
    map (\s => MkStrict (SortedMap.fromList (zip args (fromMaybe [] (lookup con s.cons)))) empty empty) strict

||| The type each operand position of `op` requires, whatever its own result representation (boxed or
||| native): a cast's source type; a string op's string and index positions; the op's own type otherwise.
opOperandTypes : PrimFn arity -> Vect arity RCLocal -> List (RCLocal, PrimType)
opOperandTypes (Cast i _) [a] = [(a, i)]
opOperandTypes StrIndex [s, i] = [(s, StringType), (i, IntType)]
opOperandTypes StrCons [c, s] = [(c, CharType), (s, StringType)]
opOperandTypes StrSubstr [i, n, s] = [(i, IntType), (n, IntType), (s, StringType)]
opOperandTypes op args = maybe [] (\ty => map (, ty) (toList args)) (ownType op)
  where
    ownType : PrimFn n -> Maybe PrimType
    ownType (Add ty) = Just ty
    ownType (Sub ty) = Just ty
    ownType (Mul ty) = Just ty
    ownType (Div ty) = Just ty
    ownType (Mod ty) = Just ty
    ownType (Neg ty) = Just ty
    ownType (ShiftL ty) = Just ty
    ownType (ShiftR ty) = Just ty
    ownType (BAnd ty) = Just ty
    ownType (BOr ty) = Just ty
    ownType (BXOr ty) = Just ty
    ownType (LT ty) = Just ty
    ownType (LTE ty) = Just ty
    ownType (EQ ty) = Just ty
    ownType (GTE ty) = Just ty
    ownType (GT ty) = Just ty
    ownType StrLength = Just StringType
    ownType StrHead = Just StringType
    ownType StrTail = Just StringType
    ownType StrReverse = Just StringType
    ownType StrAppend = Just StringType
    ownType BelieveMe = Nothing   -- no vote, as Crash
    ownType Crash = Nothing
    ownType _ = Just DoubleType   -- the Double functions

||| Every primitive type at which each of `tracked` is read anywhere in `e`, boxed reads included: an
||| operand of a primitive op or a fused comparison, or the scrutinee of a constant `case` (the type of its
||| literals). Unlike `nativeArgTypes`, which counts only the reads Emit renders natively, this counts every
||| typed read, so a conflict between branches is visible.
primReadTypesFor : SortedSet Int -> RCExp -> SortedMap Int (SortedSet PrimType)
primReadTypesFor tracked e = foldr (\(a, ty), acc => addTracked tracked a ty acc) (concatMaps (map (primReadTypesFor tracked) (children e))) (here e)
  where
    constTy : Constant -> Maybe PrimType
    constTy (Str _) = Just StringType
    constTy (BI _) = Just IntegerType
    constTy c = litRep c
    here : RCExp -> List (RCLocal, PrimType)
    here (ROp _ _ op args _) = opOperandTypes op args
    here (RCmpCase _ op args _ _ _) = map (, cmpOpTy op) (toList args)
    here (RConstCase _ sc alts _) = mapMaybe (\(MkRConstAlt c _) => map (sc,) (constTy c)) alts
    here _ = []

||| Those of `tracked` that are the scrutinee of a constructor `case` with an alternative that binds fields
||| anywhere in `e`: there the local is a heap constructor (`Maybe`, a record, a list), never a native value,
||| even if another branch reads it as one (a parameter of type `Dom o r`: a `Bool` for one `o`, a
||| `Maybe (List r)` for another). An enumeration's case (every alternative field-less, as `Bool`'s) does not
||| count.
takenApartFor : SortedSet Int -> RCExp -> SortedSet Int
takenApartFor tracked e = foldr union (here e) (map (takenApartFor tracked) (children e))
  where
    binds : RConAlt -> Bool
    binds (MkRConAlt _ _ _ args _) = not (null args)
    here : RCExp -> SortedSet Int
    here (RConCase _ (RCLoc i) alts _) = if contains i tracked && any binds alts then singleton i else empty
    here _ = empty

||| Whether `ty`, chosen for `p` from some of its reads, is consistent with the typed reads and the cases.
fits : Maybe Strict -> SortedMap Int (SortedSet PrimType) -> SortedSet Int -> Int -> NativeTy -> Bool
fits strict reads apart p ty =
    maybe True (\s => maybe False (elem ty) (lookup p s.params)) strict &&
    not (contains p apart) &&
    (let tys = maybe [] Prelude.toList (lookup p reads)
     in case ty of
             TPrim t => all (== t) tys
             _ => null tys)   -- a pointer or an erased value is no primitive's operand

||| `chosen` without the entries that do not fit the other reads of `body`, in one walk of `body` for all of
||| them: every typed primitive read of the id agrees with its type (`primReadTypesFor`; none for a pointer),
||| and no branch takes it apart as a constructor with fields (`takenApartFor`). A value whose type depends on
||| another argument (`Value (vt k)`, `Dom o r`) fails one or the other when its branches disagree.
||| See rc2/doc/native-type-inference.md's "Types that depend on a value".
export
consistentNatives : Maybe Strict -> RCExp -> SortedMap Int NativeTy -> SortedMap Int NativeTy
consistentNatives strict body chosen =
    let ids = SortedSet.fromList (keys chosen)
        reads = primReadTypesFor ids body
        apart = takenApartFor ids body
    in SortedMap.fromList (filter (\(p, ty) => fits strict reads apart p ty) (SortedMap.toList chosen))

||| `consistentNatives` for the one id `p`.
export
consistentNative : Maybe Strict -> (p : Int) -> RCExp -> NativeTy -> Bool
consistentNative strict p body ty = isJust (lookup p (consistentNatives strict body (SortedMap.singleton p ty)))

||| The single native `PrimType` top-level parameter `p` should be
||| shadowed at, if `body` reads it that way at all, and consistently
||| (every native-context use agrees on the same type) -- `Nothing` if
||| it's never read natively, or read natively at conflicting types
||| (conservatively left `RBoxed` rather than guessing). Exported for
||| `Compiler.RC2.DualABI`'s own reuse (the same "is this top-level
||| parameter read as a native operand anywhere in the body" question,
||| just asked about a whole function's own parameters rather than only
||| the ones an enclosing `RLoop` carries) -- one definition of this
||| analysis, not two kept in sync by hand.
export
nativeArgType : Maybe Strict -> Int -> RCExp -> Maybe PrimType
nativeArgType strict p body =
    case Prelude.toList (nativeArgTypes p body) of
         [ty] => if consistentNative strict p body (TPrim ty) then Just ty else Nothing
         _ => Nothing

||| Batch version of `nativeArgType`: every one of `ps`'s own verdict,
||| computed together in one walk of `body` instead of one walk per id
||| -- see "Batched, multi-id native-type analysis" below. A definition
||| with many top-level parameters (routine after lambda-lifting, which
||| turns a closure's captured environment into extra arguments) and a
||| large body would cost O(parameter count x body size) if
||| `nativeArgType` were called once per parameter; this is the same answer
||| in a single O(body size) pass.
export
nativeArgTypeBatch : Maybe Strict -> List Int -> RCExp -> SortedMap Int PrimType
nativeArgTypeBatch strict ps body =
    let found = nativeArgTypesFor (SortedSet.fromList ps) body
        chosen = SortedMap.fromList (mapMaybe (\p => map (\ty => (p, TPrim ty)) (singleTypeFrom found p)) ps)
    in SortedMap.fromList (mapMaybe (\(p, ty) => case ty of
                                                     TPrim t => Just (p, t)
                                                     _ => Nothing) (SortedMap.toList (consistentNatives strict body chosen)))

