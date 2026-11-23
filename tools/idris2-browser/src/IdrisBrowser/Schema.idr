||| The records of the index and their JSON form.
|||
||| The specification is `doc/index-format.md`; this module is its one
||| implementation, built by both the indexer and the browser.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Schema

import Data.List
import Data.Maybe
import System

import public IdrisBrowser.JSON

%default total

||| The `formatVersion` this module reads and writes.
public export
formatVersion : Integer
formatVersion = 1

||| Where the index lives unless `--index-dir` says otherwise: both programs
||| need it, the browser when no indexer is at hand.
||| `$XDG_CACHE_HOME/idris2-browser`, else `~/.cache/idris2-browser`.
export
defaultIndexDir : IO String
defaultIndexDir = do
  Just cache@(_ :: _) <- map unpack <$> getEnv "XDG_CACHE_HOME"
    | _ => do
        home <- fromMaybe "." <$> getEnv "HOME"
        pure (home ++ "/.cache/idris2-browser")
  pure (pack cache ++ "/idris2-browser")

-------------------------------------------------------------------------------
-- Enumerations

public export
data Kind = KData | KRecord | KInterface | KConstructor | KFunction
          | KForeign | KBuiltin | KHole | KOther

export
allKinds : List Kind
allKinds = [KData, KRecord, KInterface, KConstructor, KFunction, KForeign, KBuiltin, KHole, KOther]

export
kindName : Kind -> String
kindName KData = "data"
kindName KRecord = "record"
kindName KInterface = "interface"
kindName KConstructor = "constructor"
kindName KFunction = "function"
kindName KForeign = "foreign"
kindName KBuiltin = "builtin"
kindName KHole = "hole"
kindName KOther = "other"

export
Eq Kind where
  a == b = kindName a == kindName b

export
parseKind : String -> Maybe Kind
parseKind s = find (\k => kindName k == s) allKinds

public export
data DefVisibility = VPrivate | VExport | VPublic

export
Eq DefVisibility where
  VPrivate == VPrivate = True
  VExport == VExport = True
  VPublic == VPublic = True
  _ == _ = False

||| `export` and `public export`.
export
isExported : DefVisibility -> Bool
isExported VPrivate = False
isExported _ = True

export
allVisibilities : List DefVisibility
allVisibilities = [VPrivate, VExport, VPublic]

export
visibilityName : DefVisibility -> String
visibilityName VPrivate = "private"
visibilityName VExport = "export"
visibilityName VPublic = "public export"

export
parseVisibility : String -> Maybe DefVisibility
parseVisibility s = find (\v => visibilityName v == s) allVisibilities

public export
data DefTotality = TTotal | TCovering | TPartial

export
Eq DefTotality where
  TTotal == TTotal = True
  TCovering == TCovering = True
  TPartial == TPartial = True
  _ == _ = False

export
allTotalities : List DefTotality
allTotalities = [TTotal, TCovering, TPartial]

export
totalityName : DefTotality -> String
totalityName TTotal = "total"
totalityName TCovering = "covering"
totalityName TPartial = "partial"

export
parseTotality : String -> Maybe DefTotality
parseTotality s = find (\t => totalityName t == s) allTotalities

-------------------------------------------------------------------------------
-- Module files

public export
record Location where
  constructor MkLocation
  modName : String
  start : (Int, Int)
  end : (Int, Int)

public export
record Definition where
  constructor MkDefinition
  name : String
  kind : Kind
  visibility : DefVisibility
  totality : DefTotality
  typ : String
  doc : Maybe String
  location : Maybe Location

public export
record ModImport where
  constructor MkImport
  modName : String
  isPublic : Bool
  asNamespace : String

public export
record TtcInfo where
  constructor MkTtcInfo
  path : String
  bytes : Integer
  mtime : String

public export
record ModuleIndex where
  constructor MkModuleIndex
  key : String
  modName : String
  ttc : TtcInfo
  ||| `Just` the message when the module could not be read.
  error : Maybe String
  doc : Maybe String
  imports : List ModImport
  definitions : List Definition

-------------------------------------------------------------------------------
-- Packages

public export
record Dependency where
  constructor MkDependency
  name : String
  bounds : String

public export
record IpkgInfo where
  constructor MkIpkgInfo
  file : String
  version : Maybe String
  brief : Maybe String
  authors : Maybe String
  license : Maybe String
  sourcedir : Maybe String
  depends : List Dependency
  modules : List String
  main : Maybe String
  executable : Maybe String

public export
data PkgStatus = PkgOk | PkgNoIpkg | PkgUnreadable

export
Eq PkgStatus where
  PkgOk == PkgOk = True
  PkgNoIpkg == PkgNoIpkg = True
  PkgUnreadable == PkgUnreadable = True
  _ == _ = False

export
statusName : PkgStatus -> String
statusName PkgOk = "ok"
statusName PkgNoIpkg = "no-ipkg"
statusName PkgUnreadable = "unreadable"

public export
record PackageEntry where
  constructor MkPackageEntry
  key : String
  name : String
  version : Maybe String
  dir : String
  searchDir : String
  selected : Bool
  status : PkgStatus
  ttcVersions : List Integer
  ipkg : Maybe IpkgInfo
  sourcesInstalled : Bool

-------------------------------------------------------------------------------
-- Summaries

||| A count per name, in a fixed order (the order of `allKinds` etc.).
public export
Counts : Type
Counts = List (String, Integer)

public export
record Stats where
  constructor MkStats
  modulesFound : Integer
  modulesFailed : Integer
  ttcBytes : Integer
  definitions : Counts
  visibility : Counts
  totality : Counts
  exportedWithDoc : Integer
  exported : Integer
  modulesWithDoc : Integer

public export
record NameRow where
  constructor MkNameRow
  name : String
  modName : String
  kind : Kind
  visibility : DefVisibility
  hasDoc : Bool

public export
record Summary where
  constructor MkSummary
  key : String
  stats : Stats
  names : List NameRow

-------------------------------------------------------------------------------
-- The environment

public export
record SearchDir where
  constructor MkSearchDir
  path : String
  from : String

public export
record EnvInfo where
  constructor MkEnvInfo
  indexerVersion : String
  idris2Version : String
  ttcVersion : Integer
  prefixDir : String
  prefixFrom : String
  searchDirs : List SearchDir
  updated : String

-------------------------------------------------------------------------------
-- To JSON

str : String -> JSON
str = JString

int : Integer -> JSON
int = JNumber . cast

pos : (Int, Int) -> JSON
pos (l, c) = JArray [int (cast l), int (cast c)]

versioned : List (String, JSON) -> JSON
versioned kvs = JObject (("formatVersion", int formatVersion) :: kvs)

countsJSON : Counts -> JSON
countsJSON cs = JObject (map (\(k, n) => (k, int n)) cs)

locationJSON : Location -> JSON
locationJSON l = JObject [("module", str l.modName), ("start", pos l.start), ("end", pos l.end)]

definitionJSON : Definition -> JSON
definitionJSON d = JObject
  [ ("name", str d.name), ("kind", str (kindName d.kind))
  , ("visibility", str (visibilityName d.visibility))
  , ("totality", str (totalityName d.totality))
  , ("type", str d.typ), ("doc", nullable str d.doc)
  , ("location", nullable locationJSON d.location) ]

export
moduleJSON : ModuleIndex -> JSON
moduleJSON m = versioned
  [ ("key", str m.key), ("module", str m.modName)
  , ("ttc", JObject [("path", str m.ttc.path), ("bytes", int m.ttc.bytes), ("mtime", str m.ttc.mtime)])
  , ("status", str (if isJust m.error then "failed" else "ok"))
  , ("error", nullable str m.error)
  , ("doc", nullable str m.doc)
  , ("imports", JArray (map importJSON m.imports))
  , ("definitions", JArray (map definitionJSON m.definitions)) ]
  where
    importJSON : ModImport -> JSON
    importJSON i = JObject [("module", str i.modName), ("public", JBoolean i.isPublic), ("as", str i.asNamespace)]

ipkgJSON : IpkgInfo -> JSON
ipkgJSON p = JObject
  [ ("file", str p.file), ("version", nullable str p.version)
  , ("brief", nullable str p.brief), ("authors", nullable str p.authors)
  , ("license", nullable str p.license), ("sourcedir", nullable str p.sourcedir)
  , ("depends", JArray (map (\d => JObject [("name", str d.name), ("bounds", str d.bounds)]) p.depends))
  , ("modules", JArray (map str p.modules))
  , ("main", nullable str p.main), ("executable", nullable str p.executable) ]

packageJSON : PackageEntry -> JSON
packageJSON p = JObject
  [ ("key", str p.key), ("name", str p.name), ("version", nullable str p.version)
  , ("dir", str p.dir), ("searchDir", str p.searchDir)
  , ("selected", JBoolean p.selected), ("status", str (statusName p.status))
  , ("ttcVersions", JArray (map int p.ttcVersions))
  , ("ipkg", nullable ipkgJSON p.ipkg)
  , ("sources", str (if p.sourcesInstalled then "installed" else "none")) ]

export
packagesJSON : List PackageEntry -> JSON
packagesJSON ps = versioned [("packages", JArray (map packageJSON ps))]

export
summaryJSON : Summary -> JSON
summaryJSON s = versioned
  [ ("key", str s.key)
  , ("stats", JObject
      [ ("modulesFound", int s.stats.modulesFound)
      , ("modulesFailed", int s.stats.modulesFailed), ("ttcBytes", int s.stats.ttcBytes)
      , ("definitions", countsJSON s.stats.definitions)
      , ("visibility", countsJSON s.stats.visibility)
      , ("totality", countsJSON s.stats.totality)
      , ("exportedWithDoc", int s.stats.exportedWithDoc), ("exported", int s.stats.exported)
      , ("modulesWithDoc", int s.stats.modulesWithDoc) ])
  , ("names", JArray (map rowJSON s.names)) ]
  where
    rowJSON : NameRow -> JSON
    rowJSON r = JArray [ str r.name, str r.modName, str (kindName r.kind)
                       , str (visibilityName r.visibility), JBoolean r.hasDoc ]

export
envJSON : EnvInfo -> JSON
envJSON e = versioned
  [ ("indexer", JObject [ ("version", str e.indexerVersion), ("idris2Version", str e.idris2Version)
                        , ("ttcVersion", int e.ttcVersion) ])
  , ("prefix", str e.prefixDir), ("prefixFrom", str e.prefixFrom)
  , ("searchDirs", JArray (map (\d => JObject [("path", str d.path), ("from", str d.from)]) e.searchDirs))
  , ("updated", str e.updated) ]

-------------------------------------------------------------------------------
-- From JSON

req : String -> (JSON -> Maybe a) -> JSON -> Maybe a
req k f j = field k j >>= f

opt : String -> (JSON -> Maybe a) -> JSON -> Maybe (Maybe a)
opt k f j = optional f (field k j)

asPos : JSON -> Maybe (Int, Int)
asPos (JArray [l, c]) = do
  l' <- asInteger l
  c' <- asInteger c
  pure (cast l', cast c')
asPos _ = Nothing

asCounts : JSON -> Maybe Counts
asCounts (JObject kvs) = traverse (\(k, v) => (k,) <$> asInteger v) kvs
asCounts _ = Nothing

||| Refuses a file of another `formatVersion`.
checkVersion : JSON -> Maybe ()
checkVersion j = do
  v <- req "formatVersion" asInteger j
  if v == formatVersion then Just () else Nothing

asLocation : JSON -> Maybe Location
asLocation j = [| MkLocation (req "module" asString j) (req "start" asPos j) (req "end" asPos j) |]

asDefinition : JSON -> Maybe Definition
asDefinition j =
  [| MkDefinition (req "name" asString j) (req "kind" (asString >=> parseKind) j)
                  (req "visibility" (asString >=> parseVisibility) j)
                  (req "totality" (asString >=> parseTotality) j)
                  (req "type" asString j) (opt "doc" asString j)
                  (opt "location" asLocation j) |]

export
parseModule : JSON -> Maybe ModuleIndex
parseModule j = do
  checkVersion j
  t <- field "ttc" j
  ttc <- [| MkTtcInfo (req "path" asString t) (req "bytes" asInteger t) (req "mtime" asString t) |]
  imps <- req "imports" asList j >>= traverse asImport
  defs <- req "definitions" asList j >>= traverse asDefinition
  [| MkModuleIndex (req "key" asString j) (req "module" asString j) (pure ttc)
                   (opt "error" asString j) (opt "doc" asString j) (pure imps) (pure defs) |]
  where
    asImport : JSON -> Maybe ModImport
    asImport i = [| MkImport (req "module" asString i) (req "public" asBool i) (req "as" asString i) |]

asIpkg : JSON -> Maybe IpkgInfo
asIpkg j = do
  deps <- req "depends" asList j >>= traverse asDep
  mods <- req "modules" asList j >>= traverse asString
  [| MkIpkgInfo (req "file" asString j) (opt "version" asString j) (opt "brief" asString j)
                (opt "authors" asString j) (opt "license" asString j) (opt "sourcedir" asString j)
                (pure deps) (pure mods) (opt "main" asString j) (opt "executable" asString j) |]
  where
    asDep : JSON -> Maybe Dependency
    asDep d = [| MkDependency (req "name" asString d) (req "bounds" asString d) |]

asStatus : String -> Maybe PkgStatus
asStatus "ok" = Just PkgOk
asStatus "no-ipkg" = Just PkgNoIpkg
asStatus "unreadable" = Just PkgUnreadable
asStatus _ = Nothing

asPackage : JSON -> Maybe PackageEntry
asPackage j = do
  vs <- req "ttcVersions" asList j >>= traverse asInteger
  srcs <- req "sources" asString j
  [| MkPackageEntry (req "key" asString j) (req "name" asString j) (opt "version" asString j)
                    (req "dir" asString j) (req "searchDir" asString j) (req "selected" asBool j)
                    (req "status" (asString >=> asStatus) j) (pure vs) (opt "ipkg" asIpkg j)
                    (pure (srcs == "installed")) |]

export
parsePackages : JSON -> Maybe (List PackageEntry)
parsePackages j = do
  checkVersion j
  req "packages" asList j >>= traverse asPackage

export
parseSummary : JSON -> Maybe Summary
parseSummary j = do
  checkVersion j
  s <- field "stats" j
  stats <- [| MkStats (req "modulesFound" asInteger s)
                      (req "modulesFailed" asInteger s) (req "ttcBytes" asInteger s)
                      (req "definitions" asCounts s) (req "visibility" asCounts s)
                      (req "totality" asCounts s) (req "exportedWithDoc" asInteger s)
                      (req "exported" asInteger s) (req "modulesWithDoc" asInteger s) |]
  rows <- req "names" asList j >>= traverse asRow
  [| MkSummary (req "key" asString j) (pure stats) (pure rows) |]
  where
    asRow : JSON -> Maybe NameRow
    asRow (JArray [n, m, k, v, d]) =
      [| MkNameRow (asString n) (asString m) (asString k >>= parseKind)
                   (asString v >>= parseVisibility) (asBool d) |]
    asRow _ = Nothing

export
parseEnv : JSON -> Maybe EnvInfo
parseEnv j = do
  checkVersion j
  ix <- field "indexer" j
  dirs <- req "searchDirs" asList j >>= traverse asDir
  [| MkEnvInfo (req "version" asString ix) (req "idris2Version" asString ix)
               (req "ttcVersion" asInteger ix) (req "prefix" asString j)
               (req "prefixFrom" asString j) (pure dirs) (req "updated" asString j) |]
  where
    asDir : JSON -> Maybe SearchDir
    asDir d = [| MkSearchDir (req "path" asString d) (req "from" asString d) |]
