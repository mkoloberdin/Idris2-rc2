||| Bringing an index directory up to date with the environment.
|||
||| What is written, and the progress events of `--json`, are specified in
||| `doc/index-format.md`; the update rule is in `doc/design.md`, "Index".
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Index.Update

import Core.Binary
import Idris.Package.Types

import Data.Either
import Data.IORef
import Data.List
import Data.Maybe
import Data.String
import System
import System.File

import IdrisBrowser.Schema
import IdrisBrowser.Stats
import IdrisBrowser.Index.Discover
import IdrisBrowser.Index.Files
import IdrisBrowser.Index.ReadTTC

%default covering

||| Bump it whenever what is extracted changes: an index written by another
||| version is rebuilt whole.
export
indexerVersion : String
indexerVersion = "0.1.0"

public export
record Options where
  constructor MkOptions
  indexDir : String
  prefixOption : Maybe String
  json : Bool
  pretty : Bool

-------------------------------------------------------------------------------
-- Reporting

record Tally where
  constructor MkTally
  updated : Nat
  unchanged : Nat
  failed : Nat
  removed : Nat

data Result = Updated | Unchanged | Failed String

-- `--json` events go to stdout, human-readable messages to stderr.
record Reporter where
  constructor MkReporter
  json : Bool
  pretty : Bool
  tally : IORef Tally
  ||| Set when a file of the index could not be written: the run then exits 1.
  writeFailed : IORef Bool

event : Reporter -> List (String, JSON) -> IO ()
event r kvs = when r.json $ putStrLn (render (JObject kvs))

message : String -> IO ()
message s = ignore (fPutStrLn stderr s)

reportModule : Reporter -> String -> String -> Result -> IO ()
reportModule r key m res = do
  modifyIORef r.tally (count res)
  event r ([("event", JString "module"), ("key", JString key), ("module", JString m)] ++ detail res)
  case res of
    Failed err => message "\{key}: \{m}: \{err}"
    _ => pure ()
  where
    count : Result -> Tally -> Tally
    count Updated t = { updated $= S } t
    count Unchanged t = { unchanged $= S } t
    count (Failed _) t = { failed $= S } t

    detail : Result -> List (String, JSON)
    detail Updated = [("result", JString "updated")]
    detail Unchanged = [("result", JString "unchanged")]
    detail (Failed err) = [("result", JString "failed"), ("error", JString err)]

-------------------------------------------------------------------------------
-- One package

writeJSON : Reporter -> String -> JSON -> IO ()
writeJSON r path j = do
  Left err <- writeAtomic path ((if r.pretty then renderPretty else render) j)
    | Right () => pure ()
  writeIORef r.writeFailed True
  message err

-- A module file is current when it was written after its TTC (the rule of
-- `make`), so an unchanged package needs no JSON read at all.
isCurrent : (ttc : (Integer, Integer)) -> (modFile : String) -> IO Bool
isCurrent (_, ttcTime) modFile = do
  Just (_, t) <- fileStat modFile
    | Nothing => pure False
  pure (t > ttcTime)

-- Where a package's files are.
record PkgFiles where
  constructor MkPkgFiles
  key : String
  modDir : String
  summary : String

-- Read a module's TTC and write its module file. The summary is removed
-- first: if the run stops before the summary is written again, the next run
-- sees it missing instead of trusting an old one.
reindex : Reporter -> PkgFiles -> (String, String) -> IO ModuleIndex
reindex r pf (m, path) = do
  ignore (removeFile pf.summary)
  st <- fromMaybe (0, 0) <$> fileStat path
  res <- readModule path m
  let info = MkTtcInfo path (fst st) (rfc3339 (snd st))
      mi = case res of
        Right md => MkModuleIndex pf.key m info Nothing md.doc md.imports md.definitions
        Left err => MkModuleIndex pf.key m info (Just err) Nothing [] []
  writeJSON r (pf.modDir ++ "/" ++ m ++ ".json") (moduleJSON mi)
  reportModule r pf.key m (either Failed (const Updated) res)
  pure mi

-- `Left` the module when its file is current, so it is parsed only if the
-- summary has to be written again.
indexModule : Reporter -> PkgFiles -> (String, String) -> IO (Either (String, String) ModuleIndex)
indexModule r pf (m, path) = do
  st <- fromMaybe (0, 0) <$> fileStat path
  if !(isCurrent st (pf.modDir ++ "/" ++ m ++ ".json"))
    then do
      reportModule r pf.key m Unchanged
      pure (Left (m, path))
    else Right <$> reindex r pf (m, path)

-- Module files of modules that are gone (and the summary that counts them).
removeStale : Reporter -> PkgFiles -> List String -> IO ()
removeStale r pf mods = do
  let names = map (++ ".json") mods
  stale <- filter (\f => not (elem f names)) <$> Files.entries pf.modDir
  unless (isNil stale) $ ignore (removeFile pf.summary)
  for_ stale $ \f => do
    ignore (removeFile (pf.modDir ++ "/" ++ f))
    modifyIORef r.tally { removed $= S }

indexPackage : Reporter -> (indexDir : String) -> List Found -> Found -> IO PackageEntry
indexPackage r indexDir founds f = do
  let key = "\{f.name}-\{maybe "" show f.version}-\{hash8 f.dir}"
      pkgDir = indexDir ++ "/pkg/" ++ key
      pf = MkPkgFiles key (pkgDir ++ "/mod") (pkgDir ++ "/summary.json")
  ipkg <- readIpkg f.dir
  mods <- if readable f then moduleFiles f.dir else pure []
  srcs <- sourcesInstalled f.dir (map fst mods)
  when (readable f) $ do
    event r [("event", JString "package"), ("key", JString key), ("modules", JNumber (cast (length mods)))]
    createDirs pf.modDir
    results <- traverse (indexModule r pf) mods
    removeStale r pf (map fst mods)
    Nothing <- fileStat pf.summary
      | Just _ => pure ()
    ms <- traverse (load pf) results
    writeJSON r pf.summary (summaryJSON (summarise key ms))
  pure $ MkPackageEntry
    { key = key, name = f.name, version = show <$> f.version
    , dir = f.dir, searchDir = f.searchDir, selected = isSelected founds f
    , status = if not (readable f) then PkgUnreadable else if isNothing ipkg then PkgNoIpkg else PkgOk
    , ttcVersions = f.ttcVersions, ipkg = ipkg, sourcesInstalled = srcs
    }
  where
    -- A module file that no longer parses is read again from its TTC.
    load : PkgFiles -> Either (String, String) ModuleIndex -> IO ModuleIndex
    load _ (Right mi) = pure mi
    load pf (Left (m, path)) = do
      Right mi <- (>>= maybe (Left "") Right . parseModule) <$> readJSONFile (pf.modDir ++ "/" ++ m ++ ".json")
        | Left _ => do
            -- It was counted unchanged; `reindex` counts it updated.
            modifyIORef r.tally { unchanged $= (`minus` 1) }
            reindex r pf (m, path)
      pure mi

-------------------------------------------------------------------------------
-- The whole index

-- `parseEnv` already refuses another `formatVersion`.
sameWriter : EnvInfo -> Bool
sameWriter e = e.indexerVersion == indexerVersion && e.ttcVersion == cast Core.Binary.ttcVersion

run : Reporter -> Options -> IO ()
run r opts = do
  -- The module files only know their TTC's time, so an index written by
  -- another indexer or format is rebuilt whole.
  prev <- either (const Nothing) parseEnv <$> readJSONFile (opts.indexDir ++ "/env.json")
  unless (map sameWriter prev == Just True) $ removeTree (opts.indexDir ++ "/pkg")
  (prefixDir, from) <- findPrefix opts.prefixOption
  sds <- searchDirs prefixDir
  founds <- foldr (++) [] <$> traverse packagesIn sds
  event r [ ("event", JString "start"), ("indexDir", JString opts.indexDir)
          , ("packages", JNumber (cast (length founds))) ]
  message "idris2-browser-index: \{show (length founds)} packages into \{opts.indexDir}"
  pkgs <- traverse (indexPackage r opts.indexDir founds) founds
  writeJSON r (opts.indexDir ++ "/packages.json") (packagesJSON pkgs)
  t <- now
  writeJSON r (opts.indexDir ++ "/env.json") $ envJSON $ MkEnvInfo
    { indexerVersion = indexerVersion, idris2Version = idrisVersion
    , ttcVersion = cast Core.Binary.ttcVersion, prefixDir = prefixDir, prefixFrom = from
    , searchDirs = sds, updated = rfc3339 t }
  stalePkgs <- filter (\k => not (k `elem` map (.key) pkgs)) <$> Files.entries (opts.indexDir ++ "/pkg")
  for_ stalePkgs $ \k => removeTree (opts.indexDir ++ "/pkg/" ++ k)
  MkTally u n fl rm <- readIORef r.tally
  event r [ ("event", JString "done"), ("updated", JNumber (cast u)), ("unchanged", JNumber (cast n))
          , ("failed", JNumber (cast fl)), ("removed", JNumber (cast rm)) ]
  message "idris2-browser-index: \{show u} updated, \{show n} unchanged, \{show fl} failed, \{show rm} removed"

||| Run `--update`; the result is the exit code of `doc/index-format.md`.
export
update : Options -> IO Int
update opts = do
  createDirs opts.indexDir
  case !(takeLock opts.indexDir) of
    HeldBy pid => do
      message "idris2-browser-index: \{opts.indexDir} is being updated by process \{show pid}"
      pure 2
    LockFailed err => do
      message "idris2-browser-index: \{err}"
      pure 1
    Locked => do
      tally <- newIORef (MkTally 0 0 0 0)
      failed <- newIORef False
      run (MkReporter opts.json opts.pretty tally failed) opts
      releaseLock opts.indexDir
      pure (if !(readIORef failed) then 1 else 0)
