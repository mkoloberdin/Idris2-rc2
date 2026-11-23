||| Reading one installed module's TTC into index records.
|||
||| Each module is read alone into a fresh context, without its imports, the
||| way `doc/design.md` ("Reading a module") describes.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Index.ReadTTC

import Core.Context
import Core.Core
import Core.Env
import Core.FC
import Core.Normalise
import Core.TT
import Core.UnifyState
import Core.Binary
import Idris.Resugar
import Idris.Syntax
import Idris.Syntax.TTC
import Libraries.Data.ANameMap
import Libraries.Data.WithDefault

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.String

import IdrisBrowser.Schema

%default covering

-------------------------------------------------------------------------------
-- Classifying a definition

kindOf : SyntaxInfo -> Context -> GlobalDef -> Kind
kindOf syn ctxt gdef = case definition gdef of
  TCon {} =>
    if not (null (lookupName (fullname gdef) (ifaces syn))) then KInterface
    else if isRecord then KRecord else KData
  DCon {} => KConstructor
  PMDef {} => KFunction
  ExternDef {} => KForeign
  ForeignDef {} => KForeign
  Builtin {} => KBuiltin
  Hole {} => KHole
  _ => KOther
  where
    -- The rule of `getFieldsDoc` in `Idris.Doc.String`: a type whose
    -- namespace of the same name holds projections.
    isRecord : Bool
    isRecord = case displayName (fullname gdef) of
      (Just ns, n) => not (null (getFieldNames ctxt (ns <.> mkNamespace n)))
      _ => False

visibilityOf : GlobalDef -> DefVisibility
visibilityOf gdef = case collapseDefault (visibility gdef) of
  Private => VPrivate
  Export => VExport
  Public => VPublic

totalityOf : GlobalDef -> DefTotality
totalityOf gdef = case (isCovering (totality gdef), isTerminating (totality gdef)) of
  (IsCovering, IsTerminating) => TTotal
  (IsCovering, Unchecked) => TCovering
  _ => TPartial

locationOf : FC -> Maybe Location
locationOf fc = do
  nfc <- isNonEmptyFC fc
  let PhysicalIdrSrc mi = origin nfc
    | _ => Nothing
  pure (MkLocation (show mi) (startPos nfc) (endPos nfc))

-- The parser keeps the line end of the last `|||` line, and stores `""` for a
-- module without a doc comment.
cleanDoc : String -> Maybe String
cleanDoc s = case rtrim s of
  "" => Nothing
  d => Just d

-- Only names a user wrote at the top of a namespace: no `where` helpers,
-- case blocks or other machine-made names.
isUserTopName : Name -> Bool
isUserTopName (NS _ (UN _)) = True
isUserTopName _ = False

-------------------------------------------------------------------------------
-- Reading

||| What one TTC yields.
public export
record ModuleData where
  constructor MkModuleData
  doc : Maybe String
  imports : List ModImport
  definitions : List Definition

||| Read the module `modName` from the TTC at `path`.
export
readModule : (path : String) -> (modName : String) -> IO (Either String ModuleData)
readModule path modName = coreRun load (pure . Left . show) (pure . Right)
  where
    mi : ModuleIdent
    mi = nsAsModuleIdent (mkNamespace modName)

    describe : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} ->
               SyntaxInfo -> GlobalDef -> Core Definition
    describe syn gdef = do
      defs <- get Ctxt
      ty <- catch (show <$> (resugar Env.empty =<< normaliseHoles defs Env.empty (type gdef)))
                  (\_ => pure "?")
      let n = fullname gdef
      pure $ MkDefinition
        { name = show n
        , kind = kindOf syn (gamma defs) gdef
        , visibility = visibilityOf gdef
        , totality = totalityOf gdef
        , typ = ty
        , doc = lookupExact n (defDocstrings syn) >>= cleanDoc
        , location = locationOf (location gdef)
        }

    ownDef : Context -> Int -> Core (Maybe GlobalDef)
    ownDef ctxt i = do
      Just (idx, entry) <- lookupContextEntry (Resolved i) ctxt
        | Nothing => pure Nothing
      gdef <- decode ctxt idx False entry
      let Just (MkLocation m _ _) = locationOf (location gdef)
        | Nothing => pure Nothing
      pure (if m == modName && isUserTopName (fullname gdef) then Just gdef else Nothing)

    load : Core ModuleData
    load = do
      c <- newRef Ctxt !initDefs
      u <- newRef UST initUState
      s <- newRef Syn initSyntax
      Just (syn, _, imps) <- readFromTTC {extra = SyntaxInfo} False emptyFC True path mi (miAsNamespace mi)
        | Nothing => throw (InternalError "module was already loaded")
      update Syn { fixities $= merge (fixities syn), ifaces := ifaces syn }
      defs <- get Ctxt
      let ctxt = gamma defs
      -- From 0, not 1 as `allNames` does: a fresh context gives the TTC's
      -- first definition index 0.
      gdefs <- catMaybes <$> traverse (ownDef ctxt) [0 .. nextEntry ctxt - 1]
      ds <- traverse (describe syn) (sortBy (compare `on` locKey) gdefs)
      pure $ MkModuleData
        { doc = SortedMap.lookup mi (modDocstrings syn) >>= cleanDoc
        , imports = map (\(m, pub, as) => MkImport (show m) pub (show as)) imps
        , definitions = ds
        }
      where
        -- A record and its constructor share one position; the type goes first.
        locKey : GlobalDef -> ((Int, Int), Int)
        locKey gdef =
          ( maybe (0, 0) start (locationOf (location gdef))
          , case definition gdef of TCon {} => 0; _ => 1 )
