||| `--directive strictnative`: the native types each function's arguments and result may be held as,
||| from their declared types. See rc2/doc/native-type-inference.md's "The strict mode".
|||
||| Copyright 2026, Hattori,Hiroki. All rights reserved.
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.StrictNative

import Compiler.RC2.ArityRaiseCExp
import Compiler.RC2.NativeUse
import Compiler.RC2.RCExp

import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.TT
import Core.Value

import Data.List
import Data.SortedMap

%default covering

||| What a value of a declared type may be held as: `Nothing` when its representation is not shown fixed
||| (a stuck type-level application, a type variable), else the natives allowed (none for a boxed type).
Allowed : Type
Allowed = Maybe (List NativeTy)

||| One function's compiled arguments, in order, and its result.
export
record Declared where
  constructor MkDeclared
  args : List Allowed
  ret : Allowed

||| How many newtypes deep a type is looked through.
depth : Nat
depth = 8

||| The type a nullary-constructor type's values are (`Compiler.Opts.Constructor.enumTag`).
enumType : Nat -> PrimType
enumType k = if k <= 0xff then Bits8Type else if k <= 0xffff then Bits16Type else Bits32Type

||| How many binders of one type are looked at; a longer chain is cut, and what follows it is unknown.
maxBinders : Nat
maxBinders = 64

||| The binders of a normalized type (erased or not, with their types) and what is left after them, as
||| `RC2.exportCFSignature` reads them, with `IO` and newtypes of functions looked through `newtypes` deep.
binders : {auto c : Ref Ctxt Defs} -> Defs -> (newtypes : Nat) -> NF [] -> Core (List (Bool, NF []), NF [])
binders defs k t = bindersTo defs k maxBinders t
  where
    -- A newtype of a function (a record of an `IO`, as a monad over `IO` has) is that function: its
    -- definitions take the arguments of the field's type. Its other arguments are `Erased`.
    -- The constructor's own type is read without looking through its result, which is this newtype again.
    throughNewtype : Defs -> Nat -> Name -> NF [] -> Core (List (Bool, NF []), NF [])
    throughNewtype defs Z _ t = pure ([], t)
    throughNewtype defs (S k') fn t = do
        Just def <- lookupCtxtExact fn (gamma defs)
            | Nothing => pure ([], t)
        case definition def of
             TCon _ _ _ _ _ (Just [con]) _ => do
                 Just cdef <- lookupCtxtExact con (gamma defs)
                     | Nothing => pure ([], t)
                 case definition cdef of
                      DCon _ _ (Just (_, pos)) => do
                          (cbs, _) <- binders defs Z !(nf defs Env.empty (type cdef))
                          case drop pos cbs of
                               ((False, fty) :: _) => do
                                   (bs, r) <- binders defs k' fty
                                   pure (if null bs then ([], t) else (bs, r))
                               _ => pure ([], t)
                      _ => pure ([], t)
             _ => pure ([], t)

    bindersTo : Defs -> Nat -> (fuel : Nat) -> NF [] -> Core (List (Bool, NF []), NF [])
    bindersTo _ _ Z t = pure ([], t)
    bindersTo defs k (S f) (NBind fc _ (Pi _ rig _ ty) sc) = do
        aty <- evalClosure defs ty
        sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
        (rest, ret) <- bindersTo defs k f sc'
        pure ((isErased rig, aty) :: rest, ret)
    -- `IO a` is a newtype of `PrimIO a`, a function of the world: a definition of that type takes the
    -- world as one more argument and returns what the `IORes` holds.
    bindersTo defs k (S f) t@(NTCon fc n _ args) = do
        fn <- toFullNames n
        case args of
             [(_, a)] => if fn == NS (mkNamespace "PrimIO") (UN (Basic "IO"))
                            then do aty <- evalClosure defs a
                                    pure ([(False, NPrimVal fc (PrT WorldType))], aty)
                            else throughNewtype defs k fn t
             _ => throughNewtype defs k fn t
    bindersTo _ _ _ t = pure ([], t)

mutual
  ||| What a value of the normalized type `t` may be held as.
  classify : {auto c : Ref Ctxt Defs} -> Defs -> Nat -> NF [] -> Core Allowed
  classify _ Z _ = pure Nothing
  classify _ _ (NPrimVal _ (PrT WorldType)) = pure (Just [TPrim WorldType, TErased])
  classify _ _ (NPrimVal _ (PrT ty)) = pure (Just [TPrim ty])
  classify _ _ (NBind _ _ (Pi {}) _) = pure (Just [])   -- a closure
  classify _ _ (NDelayed {}) = pure (Just [])
  classify defs (S k) (NTCon _ n _ _) = typeCon defs k !(toFullNames n)
  classify _ _ _ = pure Nothing

  ||| A type constructor's values: a newtype's are its field's (upstream erases the constructor), a
  ||| nullary-constructor type's an unsigned integer, `Nat`'s an `Integer`, a type without constructors
  ||| (an external one) a pointer, any other's a boxed constructor.
  typeCon : {auto c : Ref Ctxt Defs} -> Defs -> Nat -> Name -> Core Allowed
  typeCon defs k fn = do
      Just def <- lookupCtxtExact fn (gamma defs)
          | Nothing => pure Nothing
      case definition def of
           TCon _ _ _ _ _ (Just []) _ => pure (Just [TPtr])
           TCon _ _ _ _ _ (Just [con]) _ => do
               Just cdef <- lookupCtxtExact con (gamma defs)
                   | Nothing => pure Nothing
               case definition cdef of
                    DCon _ _ (Just (_, pos)) => newtypeField defs k (type cdef) pos
                    _ => pure (byFlag (flags cdef))
           TCon _ _ _ _ _ (Just (con :: cons)) _ => do
               Just cdef <- lookupCtxtExact con (gamma defs)
                   | Nothing => pure Nothing
               pure (byFlag (flags cdef))
           _ => pure Nothing
    where
      byFlag : List DefFlag -> Allowed
      byFlag [] = Just []
      byFlag (ConType (ENUM m) :: _) = Just [TPrim (enumType m)]
      byFlag (ConType ZERO :: _) = Just [TPrim IntegerType]
      byFlag (ConType SUCC :: _) = Just [TPrim IntegerType]
      byFlag (_ :: fs) = byFlag fs

  ||| A newtype's field, judged by its declared type with the constructor's other arguments `Erased`:
  ||| a field type that mentions them is stuck, hence not shown.
  newtypeField : {auto c : Ref Ctxt Defs} -> Defs -> Nat -> ClosedTerm -> Nat -> Core Allowed
  newtypeField defs k cty pos = do
      (bs, _) <- binders defs Z !(nf defs Env.empty cty)
      case drop pos bs of
           ((False, fty) :: _) => classify defs k fty
           _ => pure Nothing

||| The binder an argument name of a compiled definition stands for: `{arg:N}` is binder `N` of the
||| case tree, `{ext:K}` the `K`th lambda after them (`Compiler.Inline.mergeLambdas`).
binderOf : (arity : Maybe Nat) -> Name -> Maybe Nat
binderOf _ (MN "arg" i) = if i >= 0 then Just (cast i) else Nothing
binderOf (Just a) (MN "ext" i) = if i >= 0 then Just (a + cast i) else Nothing
binderOf _ _ = Nothing

||| `n`'s compiled arguments `args` and result, from its declared type; `Nothing` when the arguments are not
||| ones the type accounts for. A `raised` copy takes the world, the type's last binder (the doc says why).
declaredOf : {auto c : Ref Ctxt Defs} -> (raised : Bool) -> Name -> List Name -> Core (Maybe Declared)
declaredOf raised n args = do
    defs <- get Ctxt
    -- Decoded without writing it back, as `lookupCtxtExact` does: only its type is wanted here, and
    -- keeping every definition decoded took 0.5 GB more on rc2's own build.
    Just (idx, entry) <- lookupContextEntry n (gamma defs)
        | Nothing => pure Nothing
    gdef <- decode (gamma defs) idx False entry
    let arity = case definition gdef of
                     PMDef _ as _ _ _ => Just (length as)
                     _ => Nothing
    case the (Maybe (List Nat)) (traverse (binderOf arity) args) of
         Nothing => pure Nothing
         Just is0 => do
             (bs, rest) <- binders defs depth !(nf defs Env.empty (type gdef))
             let worldIx = minus (length bs) 1
                 worldLast = case getAt worldIx bs of
                                  Just (False, NPrimVal _ (PrT WorldType)) => True
                                  _ => False
                 is = if raised then is0 ++ [worldIx] else is0
             if raised && (not worldLast || elem worldIx is0) then pure Nothing else do
             let classes = the (List (Maybe (Bool, NF []))) (map (\i => getAt i bs) is)
             if any isNothing classes then pure Nothing else do
               argCls <- traverse (\b => case b of
                                              Just (True, _) => pure (Just [TErased])
                                              Just (False, t) => classify defs depth t
                                              Nothing => pure Nothing) classes
               ret <- if foldr max 0 (map S is) == length bs then classify defs depth rest else pure Nothing
               pure (Just (MkDeclared argCls ret))

||| What each field of the constructor `n` of `arity` fields may be held as, from its declared type, in
||| field order. Upstream drops the erased arguments (`arity` counts what is left); when the declared
||| type's other binders do not come to `arity`, nothing is shown.
declaredFields : {auto c : Ref Ctxt Defs} -> Name -> Nat -> Core (List Allowed)
declaredFields n arity = do
    defs <- get Ctxt
    Just gdef <- lookupCtxtExact n (gamma defs)
        | Nothing => pure []
    (bs, _) <- binders defs Z !(nf defs Env.empty (type gdef))
    let fields = map snd (filter (not . fst) bs)
    if length fields /= arity then pure [] else
        traverse (classify defs depth) fields

||| What the declared types of a program show.
export
record Declarations where
  constructor MkDeclarations
  funs : SortedMap Name Declared
  cons : SortedMap Name (List Allowed)

||| The declared arguments and results of the functions of `defs`, and the declared fields of its
||| constructors. A copy `ArityRaiseCExp` made to take the world (its `raisedName`) has its original's
||| arguments and the world, and returns what is left.
export
declarations : {auto c : Ref Ctxt Defs} -> List (Name, FC, NamedDef) -> Core Declarations
declarations defs = do
    let origOf = SortedMap.fromList [ (raisedName n, n) | (n, _, _) <- defs ]
    own <- traverse (\(n, _, d) => case d of
                                        MkNmFun args _ =>
                                            case lookup n origOf of
                                                 Just orig => map (map (n,)) (declaredOf True orig (fromMaybe [] (init' args)))
                                                 Nothing => map (map (n,)) (declaredOf False n args)
                                        _ => pure Nothing) defs
    flds <- traverse (\(n, _, d) => case d of
                                         MkNmCon _ arity _ => map (\fs => Just (n, fs)) (declaredFields n arity)
                                         _ => pure Nothing) defs
    pure (MkDeclarations (SortedMap.fromList (mapMaybe id own)) (SortedMap.fromList (mapMaybe id flds)))

||| The table keyed by the parameter ids lowering gave each function, for the passes after it.
export
strictOf : (closed : Bool) -> Declarations -> List (Name, RCDef) -> Strict
strictOf closed decl defs =
    let matched = mapMaybe match defs
    in MkStrict closed
                (SortedMap.fromList (concatMap (\(_, ps, d) => mapMaybe (\(p, a) => map (p,) a) (zip ps d.args)) matched))
                (SortedMap.fromList (mapMaybe (\(n, _, d) => map (n,) d.ret) matched))
                decl.cons
  where
    match : (Name, RCDef) -> Maybe (Name, List LocalId, Declared)
    match (n, MkRCFun args _ _ _) = do
        d <- lookup n decl.funs
        guard (length d.args == length args)
        pure (n, map fst args, d)
    match _ = Nothing

||| `--directive dumpstrict`: one line per function, its compiled arguments and what the table shows of each.
export
dumpDeclared : Declarations -> List (Name, FC, NamedDef) -> String
dumpDeclared decl defs = concatMap line defs
  where
    showAllowed : Allowed -> String
    showAllowed = maybe "?" show

    line : (Name, FC, NamedDef) -> String
    line (n, _, MkNmFun args _) =
        show n ++ " " ++ show args ++ " = "
          ++ maybe "unknown" (\d => show (map showAllowed d.args) ++ " -> " ++ showAllowed d.ret) (lookup n decl.funs) ++ "\n"
    line _ = ""
