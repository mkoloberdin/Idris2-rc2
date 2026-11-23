||| `idris2-browser`: brings the index up to date with the indexer, then
||| runs the browser on it.
|||
||| `--dump W H [ACTION...]` draws the screen into text instead, after the
||| actions, for the tests; see `tests/verify.sh`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Main

import Data.List
import Data.String
import System
import System.Escape
import System.Posix.Errno
import System.File

import TermUI.Frame
import TermUI.Input
import TermUI.Len
import TermUI.Program
import TermUI.Widget.Select as S
import TermUI.Widget.TextInput as T

import IdrisBrowser.App
import IdrisBrowser.Schema
import IdrisBrowser.Load

%default covering

record Args where
  constructor MkArgs
  indexDir : Maybe String
  indexer : String
  noUpdate : Bool
  dump : Maybe (Len, Len, List String)

usage : String
usage = """
  usage: idris2-browser [--index-dir DIR] [--indexer PATH] [--no-update]
         idris2-browser [--index-dir DIR] --dump W H [ACTION...]
  """

parseArgs : Args -> List String -> Maybe Args
parseArgs a [] = Just a
parseArgs a ("--index-dir" :: d :: rest) = parseArgs ({ indexDir := Just d } a) rest
parseArgs a ("--indexer" :: p :: rest) = parseArgs ({ indexer := p } a) rest
parseArgs a ("--no-update" :: rest) = parseArgs ({ noUpdate := True } a) rest
parseArgs a ("--dump" :: w :: h :: actions) = do
  w' <- the (Maybe Len) (cast <$> parsePositive {a = Int} w)
  h' <- the (Maybe Len) (cast <$> parsePositive {a = Int} h)
  Just ({ dump := Just (w', h', actions), noUpdate := True } a)
parseArgs _ _ = Nothing

-------------------------------------------------------------------------------
-- Drawing into text

-- What a key would do, for the actions of `--dump`.
actionMsg : String -> Maybe AppMsg
actionMsg "pkg-down" = Just (PickPkg S.Down)
actionMsg "mod-down" = Just (PickMod S.Down)
actionMsg "def-down" = Just (PickDef S.Down)
actionMsg "filter" = Just CycleFilter
actionMsg "search" = Just OpenSearch
actionMsg "jump" = Just Jump
actionMsg s = case break (== ':') s of
  ("tab", n) => GoTab <$> parsePositive (afterColon n)
  ("type", t) => Just (Edit (T.InsertText (afterColon t)))
  _ => Nothing
  where
    afterColon : String -> String
    afterColon str = substr 1 (length str) str

-- Run the commands the way the runtime does, without a terminal.
runCmd : AppModel -> Cmd AppMsg -> IO AppModel
runCmd m NoCmd = pure m
runCmd m (Batch cs) = foldlM runCmd m cs
runCmd m (Emit msg) = step m msg
  where
    step : AppModel -> AppMsg -> IO AppModel
    step m' msg' = let (m'', c) = update msg' m' in runCmd m'' c
runCmd m (Perform io) = do
  msg <- io
  let (m', c) = update msg m
  runCmd m' c
runCmd m _ = pure m

dumpScreen : String -> Index -> (Len, Len, List String) -> IO ()
dumpScreen dir ix (w, h, actions) = do
  let (m0, c0) = initial dir ix w h
  m1 <- runCmd m0 c0
  m2 <- foldlM act m1 actions
  frame <- render (view m2) w h
  traverse_ (putStrLn . rtrim) !(frameLines frame)
  where
    act : AppModel -> String -> IO AppModel
    act m a = case actionMsg a of
      Just msg => let (m', c) = update msg m in runCmd m' c
      Nothing => do
        ignore (fPutStrLn stderr ("unknown action: " ++ a))
        pure m

-------------------------------------------------------------------------------
-- Main

main : IO ()
main = do
  _ :: args <- getArgs
    | [] => exitWith (ExitFailure 1)
  let Just a = parseArgs (MkArgs Nothing "idris2-browser-index" False Nothing) args
    | Nothing => do
        ignore (fPutStrLn stderr usage)
        exitWith (ExitFailure 1)
  let dirArgs = maybe [] (\d => ["--index-dir", d]) a.indexDir
  unless a.noUpdate $ do
    code <- system (escapeCmd (a.indexer :: dirArgs ++ ["--update"]))
    when (code /= 0) $
      ignore (fPutStrLn stderr "idris2-browser: the indexer failed (exit \{show code}); showing the index as it is")
  dir <- maybe defaultIndexDir pure a.indexDir
  Right ix <- loadIndex dir
    | Left err => do
        ignore (fPutStrLn stderr "idris2-browser: \{err}\nBuild the index with: idris2-browser-index --update")
        exitWith (ExitFailure 1)
  case a.dump of
    Just d => dumpScreen dir ix d
    Nothing => do
      let (m0, c0) = initial dir ix 80 24
      Right _ <- runProgram (MkProgram (m0, c0) update view subs)
        | Left err => do
            ignore (fPutStrLn stderr "idris2-browser needs a terminal: \{show err}")
            exitWith (ExitFailure 1)
      pure ()
