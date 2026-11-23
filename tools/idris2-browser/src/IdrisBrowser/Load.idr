||| Reading an index directory, as a reader of `doc/index-format.md`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Load

import Data.List
import Data.Maybe
import System.File

import IdrisBrowser.Schema

%default covering

||| What the browser holds at start-up: everything but the module files.
public export
record Index where
  constructor MkIndex
  env : Maybe EnvInfo
  packages : List PackageEntry
  ||| Per package key; a package not indexed yet has none.
  summaries : List (String, Summary)

||| `Left` only when `packages.json` can't be read; a missing summary leaves
||| its package without one.
export
loadIndex : (indexDir : String) -> IO (Either String Index)
loadIndex dir = do
  Right pj <- readJSONFile (dir ++ "/packages.json")
    | Left err => pure (Left err)
  let Just pkgs = parsePackages pj
    | Nothing => pure (Left "\{dir}/packages.json: not of format version \{show formatVersion}")
  env <- either (const Nothing) parseEnv <$> readJSONFile (dir ++ "/env.json")
  sums <- traverse summaryOf pkgs
  pure (Right (MkIndex env pkgs (catMaybes sums)))
  where
    summaryOf : PackageEntry -> IO (Maybe (String, Summary))
    summaryOf p = do
      Right j <- readJSONFile (dir ++ "/pkg/" ++ p.key ++ "/summary.json")
        | Left _ => pure Nothing
      pure ((p.key,) <$> parseSummary j)

||| A module file, read when its module is selected.
export
loadModule : (indexDir, key, modName : String) -> IO (Either String ModuleIndex)
loadModule dir key m = do
  let path = dir ++ "/pkg/" ++ key ++ "/mod/" ++ m ++ ".json"
  Right j <- readJSONFile path
    | Left err => pure (Left err)
  pure (maybe (Left "\{path}: not of format version \{show formatVersion}") Right (parseModule j))
