||| Finding the packages of an environment, the way `idris2` does.
|||
||| `Idris.Driver.updateEnv` and `Idris.SetOptions.findPackages` are not
||| exported, so their rules are re-implemented here; see `doc/design.md`,
||| "Finding the packages".
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Index.Discover

import Compiler.Common
import Core.Binary
import Core.Context
import Core.Core
import Idris.Package
import Idris.Package.Types
import Idris.REPL.Opts
import Idris.Syntax
import Idris.Version
import IdrisPaths
import Libraries.Utils.Path

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.Directory
import System.File

import IdrisBrowser.Schema
import IdrisBrowser.Index.Files

%default covering

-------------------------------------------------------------------------------
-- Search dirs

||| The Idris 2 version the indexer was built with, as in `idris2-0.8.0`.
export
idrisVersion : String
idrisVersion = showVersion False version

absolute : String -> IO String
absolute p =
  if isPrefixOf "/" p then pure p
  else do
    Just cwd <- currentDir
      | Nothing => pure p
    pure (cwd ++ "/" ++ p)

||| The prefix and where it came from: `--prefix`, `idris2 --prefix` of the
||| `idris2` on `PATH`, `IDRIS2_PREFIX`, or the prefix this indexer was built
||| with.
export
findPrefix : (option : Maybe String) -> IO (String, String)
findPrefix (Just p) = pure (!(absolute p), "option")
findPrefix Nothing = do
  (out, 0) <- run "idris2 --prefix 2>/dev/null"
    | _ => fallback
  let p = trim out
  if p == "" then fallback else pure (p, "idris2-on-path")
  where
    fallback : IO (String, String)
    fallback = do
      Just p <- getEnv "IDRIS2_PREFIX"
        | Nothing => pure (yprefix, "builtin")
      pure (p, "IDRIS2_PREFIX")

||| `IDRIS2_PACKAGE_PATH` in order, then the prefix's package dir.
export
searchDirs : (prefixDir : String) -> IO (List SearchDir)
searchDirs prefixDir = do
  envDirs <- maybe [] (filter (/= "") . forget . split (== ':')) <$> getEnv "IDRIS2_PACKAGE_PATH"
  envAbs <- traverse absolute envDirs
  let dirs = map (\d => MkSearchDir d "IDRIS2_PACKAGE_PATH") envAbs
             ++ [MkSearchDir (prefixDir ++ "/idris2-" ++ idrisVersion) "prefix"]
  pure (nubBy (\a, b => a.path == b.path) dirs)

-------------------------------------------------------------------------------
-- Package dirs

||| A package directory before its index is built.
public export
record Found where
  constructor MkFound
  name : String
  version : Maybe PkgVersion
  dir : String
  searchDir : String
  ttcVersions : List Integer

-- `<name>-<version>` with a dotted numeric version, or a bare name: the
-- rule of `Idris.SetOptions.pkgDir`.
splitDirName : String -> (String, Maybe PkgVersion)
splitDirName d =
  case unsnoc (split (== '-') d) of
    ([], _) => (d, Nothing)
    (front, lst) => case traverse parsePositive (split (== '.') lst) of
      Just vs => (joinBy "-" front, Just (MkPkgVersion vs))
      Nothing => (d, Nothing)

denylisted : String -> Bool
denylisted d = isPrefixOf "." d || elem d (the (List String) ["include", "lib", "support", "refc"])

export
packagesIn : SearchDir -> IO (List Found)
packagesIn sd = do
  ds <- filter (not . denylisted) <$> entries sd.path
  catMaybes <$> traverse found ds
  where
    found : String -> IO (Maybe Found)
    found d = do
      let dir = sd.path ++ "/" ++ d
      if not !(isDirectory dir)
        then pure Nothing
        else do
          vs <- mapMaybe (map cast . parsePositive {a = Int}) <$> entries dir
          let (n, v) = splitDirName d
          pure (Just (MkFound n v dir sd.path vs))

||| Whether the indexer can read the package's TTCs.
export
readable : Found -> Bool
readable f = cast Core.Binary.ttcVersion `elem` f.ttcVersions

||| Whether `idris2` would pick this copy for an unconstrained `depends`: the
||| highest version among the readable copies, the first search dir winning a
||| tie (`Idris.SetOptions.findPkgDirs`).
export
isSelected : List Found -> Found -> Bool
isSelected founds f =
  let rivals = filter (\g => g.name == f.name && readable g) founds
      best = head' (sortBy (\x, y => compare y.version x.version) rivals)
   in readable f && map (.dir) best == Just f.dir

-------------------------------------------------------------------------------
-- The installed ipkg

boundsText : PkgVersionBounds -> String
boundsText b =
  if isNothing b.lowerBound && isNothing b.upperBound then "" else show b

||| Parse the installed `.ipkg` of a package dir, if there is exactly one.
export
readIpkg : (dir : String) -> IO (Maybe IpkgInfo)
readIpkg dir = do
  [f] <- filter (isSuffixOf ".ipkg") <$> entries dir
    | _ => pure Nothing
  let file = dir ++ "/" ++ f
  coreRun (parse file) (\_ => pure Nothing) (pure . Just)
  where
    parse : String -> Core IpkgInfo
    parse file = do
      c <- newRef Ctxt !initDefs
      s <- newRef Syn initSyntax
      o <- newRef ROpts (defaultOpts Nothing (REPL InfoLvl) [])
      pkg <- parsePkgFile False file
      pure $ MkIpkgInfo
        { file = file
        , version = show <$> pkg.version
        , brief = pkg.brief
        , authors = pkg.authors
        , license = pkg.license
        , sourcedir = pkg.sourcedir
        , depends = map (\d => MkDependency d.pkgname (boundsText d.pkgbounds)) pkg.depends
        , modules = map (show . fst) pkg.modules
        , main = show . fst <$> pkg.mainmod
        , executable = pkg.executable
        }

||| The modules of a package: every `.ttc` under `<dir>/<ttcVersion>/`, as
||| `(module name, path)`.
export
moduleFiles : (dir : String) -> IO (List (String, String))
moduleFiles dir = walk [] (dir ++ "/" ++ show Core.Binary.ttcVersion)
  where
    walk : List String -> String -> IO (List (String, String))
    walk ns path = do
      es <- entries path
      foldr (++) [] <$> for es (\e => do
        let p = path ++ "/" ++ e
        if !(isDirectory p)
          then walk (ns ++ [e]) p
          else pure $ case stripSuffix ".ttc" e of
            Just m => [(joinBy "." (ns ++ [m]), p)]
            Nothing => [])
      where
        stripSuffix : String -> String -> Maybe String
        stripSuffix suf s =
          if isSuffixOf suf s then Just (substr 0 (length s `minus` length suf) s) else Nothing

||| Whether the sources were installed with the package
||| (`--install-with-src` puts them right under the package dir).
export
sourcesInstalled : (dir : String) -> (modules : List String) -> IO Bool
sourcesInstalled dir modules = case modules of
  m :: _ => do
    let base = dir ++ "/" ++ joinBy "/" (forget (split (== '.') m))
    anyM (\ext => isJust <$> fileStat (base ++ "." ++ ext)) ["idr", "lidr", "md", "org", "tex"]
  [] => pure False
  where
    anyM : (a -> IO Bool) -> List a -> IO Bool
    anyM _ [] = pure False
    anyM f (x :: xs) = if !(f x) then pure True else anyM f xs
