||| Fields of constant constructors that no `case` alt of the program ever
||| binds lose the closure they hold, so dead code elimination can drop the
||| function behind it (an `Ord` dictionary's `max`, say). See
||| `rc2/doc/dead-fields.md`, "Constant constructors". Whole program only;
||| disable with `--directive noconstfields`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module Compiler.RC2.ConstFields

import Compiler.RC2.ConstFold
import Compiler.RC2.FunDedup
import Compiler.RC2.RCExp

import Core.Name

import Data.List
import Data.List.Quantifiers
import Data.SortedMap
import Data.SortedSet

%default covering

||| What the program may read of its constructors: per constructor, the
||| fields some alt binds, and the constructors read field by field some
||| other way (a struct return), of which every field counts as read.
record Reads where
  constructor MkReads
  bound : SortedMap Name (SortedSet Nat)
  whole : SortedSet Name

reads : List (Name, RCDef) -> Reads
reads defs = foldl def (MkReads empty empty) defs
  where
    alt : Reads -> RConAlt -> Reads
    alt r (MkRConAlt n _ _ args _) =
      let used = map fst (filter (not . isDeadId . snd) (zip [0 .. length args] args))
      in { bound $= insertWith union n (SortedSet.fromList used) } r

    walk : Reads -> List RCExp -> Reads
    walk r [] = r
    walk r (e :: es) = case e of
      RConCase _ _ alts _ => walk (foldl alt r alts) (children e ++ es)
      RRetPack _ n _ _ => walk ({ whole $= insert n } r) es
      _ => walk r (children e ++ es)

    def : Reads -> (Name, RCDef) -> Reads
    def r (_, MkRCFun _ _ _ body) = walk r [body]
    def r (_, MkRCError body) = walk r [body]
    def r _ = r

||| `l` with every constant closure that sits in an unread field of a constant
||| constructor replaced by `[erased]`. Only closures: the runtime reads no
||| closure out of a program's data, and a closure is what keeps a function
||| alive. The erased proofs are taken again, as in `FunDedup.renameLocalN`.
prune : Reads -> SortedSet Name -> RCLocal -> RCLocal
prune rs newtypes = go
  where
    unread : Name -> Nat -> Bool
    unread n i =
      not (contains n rs.whole) && not (contains n newtypes)
        && not (maybe False (contains i) (lookup n rs.bound))

    go : RCLocal -> RCLocal
    go c@(RCConstCon n ci tag args) =
      let args' = zipWith (\i, a => case a of
                                      RCConstPartial {} => if unread n i then RCErased else go a
                                      _ => go a) [0 .. length args] args
      in case allConstLocal args' of
              Just prf => RCConstCon n ci tag args' {argsConst = prf}
              Nothing => c
    go c@(RCConstPartial n missing caps) =
      let caps' = map go caps
      in case allConstLocal caps' of
              Just prf => RCConstPartial n missing caps' {capsConst = prf}
              Nothing => c
    go l = l

export
applyConstFields : List (Name, RCDef) -> List (Name, RCDef)
applyConstFields defs =
    let rs = reads defs
        newtypes : SortedSet Name := SortedSet.fromList (mapMaybe (\(n, d) => case d of
                                                             MkRCCon _ _ (Just _) => Just n
                                                             _ => Nothing) defs)
        p = prune rs newtypes
    in map (\(n, d) => (n, case d of
                               MkRCFun args r w body => MkRCFun args r w (mapLocalsR p body)
                               MkRCError body => MkRCError (mapLocalsR p body)
                               _ => d)) defs
