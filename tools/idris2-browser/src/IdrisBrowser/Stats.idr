||| Statistics of packages, from their module files or summaries.
|||
||| Pure, and built by both programs: the indexer writes a package's figures
||| into its `summary.json`, the browser adds summaries up for the whole
||| environment. The figures are defined in `doc/index-format.md`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Stats

import Data.List
import Data.Maybe

import IdrisBrowser.Schema

%default total

countBy : Eq a => (a -> String) -> List a -> List a -> Counts
countBy name universe xs =
  map (\u => (name u, cast (length (filter (== u) xs)))) universe

||| The summary of one package from its module files.
export
summarise : (key : String) -> List ModuleIndex -> Summary
summarise key mods =
  let defs = foldr (\m, acc => m.definitions ++ acc) [] mods
      exported = filter (isExported . (.visibility)) defs
   in MkSummary
        { key = key
        , stats = MkStats
            { modulesFound = cast (length mods)
            , modulesFailed = cast (length (filter (isJust . (.error)) mods))
            , ttcBytes = sum (map (.ttc.bytes) mods)
            , definitions = countBy kindName allKinds (map (.kind) defs)
            , visibility = countBy visibilityName allVisibilities (map (.visibility) defs)
            , totality = countBy totalityName allTotalities (map (.totality) defs)
            , exportedWithDoc = cast (length (filter (isJust . (.doc)) exported))
            , exported = cast (length exported)
            , modulesWithDoc = cast (length (filter (isJust . (.doc)) mods))
            }
        , names = foldr (\m, acc => rows m ++ acc) [] mods
        }
  where
    rows : ModuleIndex -> List NameRow
    rows m = map (\d => MkNameRow d.name m.modName d.kind d.visibility (isJust d.doc)) m.definitions

addCounts : Counts -> Counts -> Counts
addCounts xs ys =
  map (\(k, n) => (k, n + fromMaybe 0 (lookup k ys))) xs
  ++ filter (\(k, _) => isNothing (lookup k xs)) ys

||| The figures of several packages added up.
export
addUp : List Stats -> Stats
addUp = foldl add zero
  where
    zero : Stats
    zero = MkStats 0 0 0 [] [] [] 0 0 0

    add : Stats -> Stats -> Stats
    add a b = MkStats
      { modulesFound = a.modulesFound + b.modulesFound
      , modulesFailed = a.modulesFailed + b.modulesFailed
      , ttcBytes = a.ttcBytes + b.ttcBytes
      , definitions = addCounts a.definitions b.definitions
      , visibility = addCounts a.visibility b.visibility
      , totality = addCounts a.totality b.totality
      , exportedWithDoc = a.exportedWithDoc + b.exportedWithDoc
      , exported = a.exported + b.exported
      , modulesWithDoc = a.modulesWithDoc + b.modulesWithDoc
      }
