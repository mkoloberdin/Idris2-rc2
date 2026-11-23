||| The browser as a termui program: its model, messages, update and view.
|||
||| The screen is described in `doc/design.md`, "User interface".
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.App

import Data.Fin
import Data.List
import Data.Maybe
import Data.String
import System.Directory

import TermUI.Input
import TermUI.Len
import TermUI.Node
import TermUI.Program
import TermUI.Style
import TermUI.Markdown.Theme
import TermUI.Widget.KeyGuide
import TermUI.Widget.MarkdownView as MD
import TermUI.Widget.Select as S
import TermUI.Widget.TabStrip as Tab
import TermUI.Widget.TextInput as T

import IdrisBrowser.Schema
import IdrisBrowser.Stats
import IdrisBrowser.Load

%default covering

-------------------------------------------------------------------------------
-- Model

||| What the Definitions list shows.
public export
data Filter = Exported | Everything | Undocumented

filterName : Filter -> String
filterName Exported = "exported"
filterName Everything = "all"
filterName Undocumented = "exported, no doc"


||| A hit of the search across the environment.
record Hit where
  constructor MkHit
  hitKey : String
  row : NameRow

public export
record AppModel where
  constructor MkModel
  indexDir : String
  index : Index
  width : Len
  height : Len
  pkgs : S.Model
  mods : S.Model
  defs : S.Model
  ||| The module file of the selected module, once read.
  current : Maybe ModuleIndex
  ||| The definitions the Definitions list shows, in its order.
  shown : List Definition
  filter : Filter
  tabs : Tab.Model
  pane : MD.Model
  ||| `Just` while the search is open.
  search : Maybe T.Model
  hits : S.Model
  hitList : List Hit
  ||| Every name of the environment with its lower-case form, made once.
  names : List (String, NameRow, String)
  ||| The module and definition a jump goes to, until its module file is read.
  pending : Maybe (String, String)

public export
data AppMsg
  = PickPkg S.Msg | PickMod S.Msg | PickDef S.Msg | PickHit S.Msg
  | FromTab Tab.Msg | Scroll MD.ViewMsg | Edit T.Msg
  | ModsListed (List String) | Loaded String (Either String ModuleIndex)
  | Resize Len Len | GoTab Nat | CycleFilter | OpenSearch | CloseSearch | Jump | Quit'

-------------------------------------------------------------------------------
-- Layout

-- The top half holds the three lists, the bottom half the tabbed pane; the
-- key guide takes the last row.
topRows : Len -> Len
topRows h = max 5 ((h `monus` 1) `div` 2)

listRows : Len -> Len
listRows h = topRows h `monus` 3

paneRows : Len -> Len
paneRows h = (h `monus` (topRows h + 1)) `monus` 3

paneCols : Len -> Len
paneCols w = w `monus` 2

-------------------------------------------------------------------------------
-- Selections

selectedPkg : AppModel -> Maybe PackageEntry
selectedPkg m = head' (drop (cast m.pkgs.selected) m.index.packages)


selectedMod : AppModel -> Maybe String
selectedMod = S.current . (.mods)

selectedDef : AppModel -> Maybe Definition
selectedDef m = head' (drop (cast m.defs.selected) m.shown)

pkgLabel : PackageEntry -> String
pkgLabel p =
  let mark = case p.status of
               PkgUnreadable => " !"
               _ => if p.selected then "" else " ~"
   in p.name ++ maybe "" (" " ++) p.version ++ mark

shortName : (modName : String) -> String -> String
shortName m n = fromMaybe n (stripPrefix' (m ++ ".") n)
  where
    stripPrefix' : String -> String -> Maybe String
    stripPrefix' pre s =
      if isPrefixOf pre s then Just (substr (length pre) (length s `minus` length pre) s) else Nothing

||| Whether the Definitions list shows a definition of this visibility, with or
||| without a doc comment.
passes : Filter -> DefVisibility -> (hasDoc : Bool) -> Bool
passes Exported v _ = isExported v
passes Everything _ _ = True
passes Undocumented v d = isExported v && not d

defLabel : String -> Definition -> String
defLabel m d =
  kindTag d.kind ++ shortName m d.name ++ (case d.visibility of VPrivate => "  (private)"; _ => "")
  where
    kindTag : Schema.Kind -> String
    kindTag KData = "data "
    kindTag KRecord = "rec  "
    kindTag KInterface = "ifc  "
    kindTag KConstructor = "con  "
    kindTag KFunction = "fn   "
    kindTag KForeign = "ffi  "
    kindTag KBuiltin = "prim "
    kindTag KHole = "hole "
    kindTag KOther = "?    "

-------------------------------------------------------------------------------
-- The pane

-- Nothing folds (the pane is refilled on every move, so a fold would not
-- last), and the language of a code block is always Idris.
theme : MdTheme
theme = { fold := const NoFold, headingMark := const "", showLang := False } defaultTheme

-- The pane shows the active tab from its top (a new viewer follows the end of
-- its text); it is filled again whenever what it shows
-- may have changed, which also scrolls it back to the top.
refreshPane : AppModel -> AppModel
refreshPane m =
  let txt = case Tab.activeIndex m.tabs of
              0 => docText m
              1 => typeText m
              2 => statsText m
              _ => packageText m
   in { pane := { follow := False, top := 0 } (MD.addSegment txt (MD.empty theme (paneRows m.height) (paneCols m.width))) } m
  where
    bullet : String -> String -> String
    bullet k v = "- **\{k}**: \{v}"

    definitionText : String -> Definition -> String
    definitionText m d = unlines
      [ "### " ++ shortName m d.name, ""
      , "```idris", shortName m d.name ++ " : " ++ d.typ, "```", ""
      , fromMaybe "*No documentation.*" d.doc ]

    docText : AppModel -> String
    docText m = case m.current of
      Nothing => if isJust (selectedMod m) then "*Reading the module...*" else "*No module.*"
      Just mi =>
        let modPart = "## " ++ mi.modName ++ "\n\n" ++ fromMaybe "*No module documentation.*" mi.doc
         in case (mi.error, selectedDef m) of
              (Just err, _) => "## " ++ mi.modName ++ "\n\nThe indexer could not read this module:\n\n    " ++ err
              (Nothing, Just d) => definitionText mi.modName d ++ "\n---\n\n" ++ modPart
              (Nothing, Nothing) => modPart

    typeText : AppModel -> String
    typeText m = case (m.current, selectedDef m) of
      (Just mi, Just d) => unlines
        [ "```idris", d.name ++ " : " ++ d.typ, "```", ""
        , bullet "kind" (kindName d.kind)
        , bullet "visibility" (visibilityName d.visibility)
        , bullet "totality" (totalityName d.totality)
        , bullet "location" (maybe "unknown" (\l => "\{l.modName} line \{show (fst l.start + 1)}") d.location) ]
      _ => "*No definition.*"

    statsLines : Stats -> List String
    statsLines s =
      [ bullet "modules" "\{show s.modulesFound} (\{show s.modulesFailed} failed, \{show s.modulesWithDoc} with a module doc)"
      , bullet "TTC size" "\{show (s.ttcBytes `div` 1024)} KiB"
      , bullet "definitions" (counts s.definitions)
      , bullet "visibility" (counts s.visibility)
      , bullet "totality" (counts s.totality)
      , bullet "documented" "\{show s.exportedWithDoc} of \{show s.exported} exported (\{percent s.exportedWithDoc s.exported})" ]
      where
        counts : Counts -> String
        counts cs = joinBy ", " [ "\{k} \{show n}" | (k, n) <- cs, n /= 0 ]

        percent : Integer -> Integer -> String
        percent _ 0 = "-"
        percent a b = show ((a * 100) `div` b) ++ "%"

    statsText : AppModel -> String
    statsText m =
      let env = addUp (map (.stats . snd) m.index.summaries)
          pkgPart = case selectedPkg m of
            Just p => case lookup p.key m.index.summaries of
              Just s => ["## " ++ pkgLabel p, ""] ++ statsLines s.stats ++ [""]
              Nothing => ["## " ++ pkgLabel p, "", "*Not indexed.*", ""]
            Nothing => []
          problems = filter (\p => case p.status of PkgOk => False; _ => True) m.index.packages
          several = nub [ p.name | p <- m.index.packages, length (filter (\q => q.name == p.name) m.index.packages) > 1 ]
       in unlines $ pkgPart ++
            [ "## Environment", "" ]
            ++ maybe [] (\e => [ bullet "prefix" "\{e.prefixDir} (from \{e.prefixFrom})"
                               , bullet "indexed" "\{e.updated} by idris2-browser-index \{e.indexerVersion}" ]) m.index.env
            ++ [ bullet "packages" "\{show (length m.index.packages)} (\{show (length m.index.summaries)} indexed)" ]
            ++ statsLines env
            ++ (if null problems then [] else ["", "### Not usable", ""] ++ map (\p => "- " ++ pkgLabel p ++ ": " ++ statusName p.status) problems)
            ++ (if null several then [] else ["", "### Installed more than once", ""] ++ map ("- " ++) several)

    packageText : AppModel -> String
    packageText m = case selectedPkg m of
      Nothing => "*No package.*"
      Just p =>
        let deps = maybe [] (.depends) p.ipkg
            users = [ q.name | q <- m.index.packages, any (\d => d.name == p.name) (maybe [] (.depends) q.ipkg) ]
         in unlines $
              [ "## " ++ pkgLabel p, ""
              , bullet "directory" p.dir
              , bullet "search dir" p.searchDir
              , bullet "status" (statusName p.status)
              , bullet "selected by idris2" (if p.selected then "yes" else "no")
              , bullet "sources" (if p.sourcesInstalled then "installed" else "not installed")
              , bullet "TTC versions" (joinBy ", " (map show p.ttcVersions))
              , "", "### Depends on", "" ]
              ++ (if null deps then ["*Nothing.*"] else map (\d => "- " ++ d.name ++ (if d.bounds == "" then "" else " " ++ d.bounds)) deps)
              ++ ["", "### Used by", ""]
              ++ (if null users then ["*Nothing installed.*"] else map ("- " ++) (nub users))

-------------------------------------------------------------------------------
-- Update

refreshDefs : AppModel -> AppModel
refreshDefs m =
  let ds = maybe [] (\mi => filter (\d => passes m.filter d.visibility (isJust d.doc)) mi.definitions) m.current
      labels = maybe [] (\mi => map (defLabel mi.modName) ds) m.current
   in { shown := ds, defs $= S.setItems labels } m

modulesOf : String -> PackageEntry -> IO (List String)
modulesOf dir p = do
  Right es <- listDir (dir ++ "/pkg/" ++ p.key ++ "/mod")
    | Left _ => pure []
  pure (sort (mapMaybe dropJson es))
  where
    dropJson : String -> Maybe String
    dropJson e = if isSuffixOf ".json" e then Just (substr 0 (length e `minus` 5) e) else Nothing


-- A new package: list its modules, then read the first.
pkgChanged : AppModel -> (AppModel, Cmd AppMsg)
pkgChanged m = case selectedPkg m of
  Nothing => (m, NoCmd)
  Just p => (m, Perform (do
    ms <- modulesOf m.indexDir p
    pure (ModsListed ms)))

modChanged : AppModel -> (AppModel, Cmd AppMsg)
modChanged m =
  let m' = refreshPane (refreshDefs ({ current := Nothing, defs := S.fromList (listRows m.height) [] } m))
   in (m', loadCmd m')
  where
    loadCmd : AppModel -> Cmd AppMsg
    loadCmd m = case (selectedPkg m, selectedMod m) of
      (Just p, Just mn) => Perform (Loaded mn <$> loadModule m.indexDir p.key mn)
      _ => NoCmd

-- Select the item with this label, if the list has it.
selectLabel : String -> S.Model -> S.Model
selectLabel l s = case findIndex (== l) s.items of
  Just i => S.resize s.rows ({ selected := cast (finToNat i) } s)
  Nothing => s



export
update : AppMsg -> AppModel -> (AppModel, Cmd AppMsg)
update (PickPkg e) m =
  let m' = { pkgs $= S.update e } m in
  if m'.pkgs.selected == m.pkgs.selected then (m', NoCmd) else pkgChanged m'
update (PickMod e) m =
  let m' = { mods $= S.update e } m in
  if m'.mods.selected == m.mods.selected then (m', NoCmd) else modChanged m'
update (PickDef e) m = (refreshPane ({ defs $= S.update e } m), NoCmd)
update (PickHit e) m = ({ hits $= S.update e } m, NoCmd)
update (FromTab e) m = (refreshPane ({ tabs $= Tab.update e } m), NoCmd)
update (GoTab n) m = (refreshPane ({ tabs $= Tab.select n } m), NoCmd)
update (Scroll e) m = ({ pane $= MD.update e } m, NoCmd)
update (ModsListed ms) m =
  let mods' = S.fromList (listRows m.height) ms
      picked : S.Model
      picked = case m.pending of
                 Just (mn, _) => selectLabel mn mods'
                 Nothing => mods'
   in modChanged ({ mods := picked } m)
update (Loaded mn res) m =
  if Just mn /= selectedMod m then (m, NoCmd)
  else
    let mi = either (\err => MkModuleIndex "" mn (MkTtcInfo "" 0 "") (Just err) Nothing [] []) id res
        m1 = refreshDefs ({ current := Just mi, pending := Nothing } m)
        m2 = case m.pending >>= (\(_, n) => find (\d => d.name == n) m1.shown) of
               Just d => { defs $= selectLabel (defLabel mn d) } m1
               Nothing => m1
     in (refreshPane m2, NoCmd)
update (Resize w h) m =
  let m' = { width := w, height := h
           , pkgs $= S.resize (listRows h), mods $= S.resize (listRows h)
           , defs $= S.resize (listRows h), hits $= S.resize (h `monus` 6) } m
   in (refreshPane m', NoCmd)
update CycleFilter m =
  let m' = refreshDefs ({ filter $= nextFilter } m)
   in (refreshPane m', NoCmd)
  where
    nextFilter : Filter -> Filter
    nextFilter Exported = Everything
    nextFilter Everything = Undocumented
    nextFilter Undocumented = Exported
update OpenSearch m =
  if isJust m.search then (m, NoCmd)
  else ({ search := Just (T.empty (m.width `monus` 12)), hitList := [], hits $= S.setItems [] } m, NoCmd)
update CloseSearch m = ({ search := Nothing } m, NoCmd)
update (Edit e) m = case m.search of
  Nothing => (m, NoCmd)
  Just t =>
    let t' = T.update e t
        hs = searchFor (toLower (T.value t')) 500 m.names
     in ({ search := Just t', hitList := hs, hits $= S.setItems (map (hitLabel m) hs) } m, NoCmd)
  where
    -- The first `n` hits, without looking further.
    searchFor : String -> Nat -> List (String, NameRow, String) -> List Hit
    searchFor "" _ _ = []
    searchFor _ Z _ = []
    searchFor _ _ [] = []
    searchFor q (S n) ((k, r, low) :: rest) =
      if isInfixOf q low then MkHit k r :: searchFor q n rest else searchFor q (S n) rest

    hitLabel : AppModel -> Hit -> String
    hitLabel m h =
      let pkg = maybe h.hitKey pkgLabel (find (\p => p.key == h.hitKey) m.index.packages)
       in h.row.name ++ "  (" ++ pkg ++ ")"
update Jump m = case head' (drop (cast m.hits.selected) m.hitList) of
  Nothing => (m, NoCmd)
  Just h => case findIndex (\p => p.key == h.hitKey) m.index.packages of
    Nothing => (m, NoCmd)
    Just i =>
      let m' = { search := Nothing, pending := Just (h.row.modName, h.row.name)
               , filter := if passes m.filter h.row.visibility h.row.hasDoc then m.filter else Everything
               , pkgs $= (\s => S.resize s.rows ({ selected := cast (finToNat i) } s)) } m
       in case selectedPkg m' of
            Nothing => (m', NoCmd)
            Just p => (m', Perform (do
              ms <- modulesOf m.indexDir p
              pure (ModsListed ms)))
update Quit' m = (m, Quit)

-------------------------------------------------------------------------------
-- View

titled : String -> Len -> Node AppMsg -> Node AppMsg
titled t g body = box [border Single, grow g] [styled (withAttr Bold plain) t, body]

hints : List (Hint AppMsg)
hints =
  [ MkHint 1 "Doc" (GoTab 0), MkHint 2 "Type" (GoTab 1), MkHint 3 "Stats" (GoTab 2)
  , MkHint 4 "Package" (GoTab 3), MkHint 5 "Filter" CycleFilter, MkHint 6 "Search" OpenSearch
  , MkHint 10 "Quit" Quit' ]



export
view : AppModel -> Node AppMsg
view m = maybe (browseView m) (searchView m) m.search
  where
    browseView : AppModel -> Node AppMsg
    browseView m =
      column [grow 1]
        [ row [height (Cells (topRows m.height))]
            [ titled "Packages" 2 (S.list PickPkg m.pkgs)
            , titled "Modules" 3 (S.list PickMod m.mods)
            , titled ("Definitions (" ++ filterName m.filter ++ ")") 4 (S.list PickDef m.defs) ]
        , Tab.tabbed FromTab m.tabs [MD.viewer Scroll m.pane, MD.viewer Scroll m.pane, MD.viewer Scroll m.pane, MD.viewer Scroll m.pane]
        , keyGuide hints ]

    searchView : AppModel -> T.Model -> Node AppMsg
    searchView m t =
      column [grow 1]
        [ row [gap 1] [text "Search:", box [border Single, grow 1] [T.field Edit (Just Jump) t]]
        , box [border Single, grow 1]
            [ text "\{show (length m.hitList)} hits (Enter jumps, Esc closes)"
            , S.list PickHit m.hits ]
        ]

export
subs : AppModel -> List (Sub AppMsg)
subs m =
  [ MouseFocus
  , OnResize Resize
  , OnInput $ \i => case keyInput hints i of
      Just msg => Just msg
      Nothing => case (m.search, i) of
        (_, Press (KChar 'c') (MkMods _ True _)) => Just Quit'
        (Just _, Press KEscape _) => Just CloseSearch
        (Just _, Press KEnter _) => Just Jump
        -- The focus is an index, so the search may open with it on the list
        -- of hits: the field's keys are taken here too (the field, when it
        -- has the focus, takes them first).
        (Just _, Press (KChar c) mods) => if mods.ctrl || mods.alt then Nothing else Just (Edit (T.Insert c))
        (Just _, Press KBackspace _) => Just (Edit T.Backspace)
        (Just _, Paste s) => Just (Edit (T.InsertText s))
        (Just _, Press KUp _) => Just (PickHit S.Up)
        (Just _, Press KDown _) => Just (PickHit S.Down)
        (Just _, Press KPageUp _) => Just (PickHit S.PageUp)
        (Just _, Press KPageDown _) => Just (PickHit S.PageDown)
        (Nothing, Press KEscape _) => Just Quit'
        (Nothing, Press (KChar 'q') _) => Just Quit'
        (Nothing, Press (KChar '/') _) => Just OpenSearch
        (Nothing, Press (KChar 'f') _) => Just CycleFilter
        _ => Nothing
  ]

||| The model at start-up, for a screen of `w` by `h` cells, and the command
||| that lists the first package's modules.
export
initial : (indexDir : String) -> Index -> (w, h : Len) -> (AppModel, Cmd AppMsg)
initial dir ix w h =
  let m = MkModel
            { indexDir = dir, index = ix, width = w, height = h
            , pkgs = S.fromList (listRows h) (map pkgLabel ix.packages)
            , mods = S.fromList (listRows h) [], defs = S.fromList (listRows h) []
            , current = Nothing, shown = [], filter = Exported
            , tabs = Tab.fromTitles ["Doc", "Type", "Stats", "Package"]
            , pane = MD.empty theme (paneRows h) (paneCols w)
            , search = Nothing, hits = S.fromList (h `monus` 6) [], hitList = []
            , pending = Nothing
            , names = [ (k, r, toLower r.name) | (k, s) <- ix.summaries, r <- s.names ] }
   in pkgChanged (refreshPane m)
