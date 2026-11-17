||| Gives `Data.Nat.isLTE` and `Data.Nat.lte` definitions that compare the two numbers once,
||| where upstream's take them apart one `S` at a time (`rc2/doc/nat-magic.md`). Upstream's own
||| `natHack` (`Compiler.Opts.Constructor`) does this for `plus`, `minus`, `compareNat` and a few
||| more of `Prelude.Types`, not for these two of `Data.Nat`. Disable with `--directive nonatmagic`.
|||
||| Copyright 2026, Hattori,Hiroki. All rights reserved.
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.NatMagic

import Core.CompileExpr
import Core.Context
import Core.TT

import Data.Vect

%default covering

isFun : String -> Name -> Bool
isFun s n = show n == s

prelude : String -> Name
prelude s = NS (mkNamespace "Prelude.Types") (UN (Basic s))

||| A `Bool` from an `Int` comparison result, as upstream makes `prim__lte_Integer`'s.
asBool : NamedCExp -> NamedCExp
asBool cmp = NmConstCase emptyFC cmp [MkNConstAlt (I 0) (NmPrimVal emptyFC (B8 0))] (Just (NmPrimVal emptyFC (B8 1)))

||| `lte m n = m <= n`.
lteBody : Name -> Name -> NamedCExp
lteBody m n = asBool (NmOp emptyFC (LTE IntegerType) [NmLocal emptyFC m, NmLocal emptyFC n])

||| `isLTE m n = if m <= n then Yes prf else No contra`. The proof `LTESucc (... LTEZero)` is
||| represented as the number of its `LTESucc`s (`LTE` is a type of `Nat`'s shape), which is `m`.
||| The refutation is a function to `Void`: nothing can call it with a proof, so it only crashes.
isLTEBody : Name -> Name -> NamedCExp
isLTEBody m n =
    NmConstCase emptyFC (NmOp emptyFC (LTE IntegerType) [NmLocal emptyFC m, NmLocal emptyFC n])
        [MkNConstAlt (I 0) (NmCon emptyFC (prelude "No") DATACON (Just 1)
                                [NmLam emptyFC (MN "rc2_lteProof" 0) (NmCrash emptyFC "Data.Nat.isLTE: there is no proof of this LTE")])]
        (Just (NmCon emptyFC (prelude "Yes") DATACON (Just 0) [NmLocal emptyFC m]))

||| `defs` with the definitions of `Data.Nat.isLTE` and `Data.Nat.lte` replaced, each with its own
||| parameters.
export
applyNatMagic : List (Name, FC, NamedDef) -> List (Name, FC, NamedDef)
applyNatMagic = map replace
  where
    replace : (Name, FC, NamedDef) -> (Name, FC, NamedDef)
    replace (n, fc, MkNmFun [m, k] body) =
        if isFun "Data.Nat.isLTE" n then (n, fc, MkNmFun [m, k] (isLTEBody m k))
        else if isFun "Data.Nat.lte" n then (n, fc, MkNmFun [m, k] (lteBody m k))
        else (n, fc, MkNmFun [m, k] body)
    replace d = d
