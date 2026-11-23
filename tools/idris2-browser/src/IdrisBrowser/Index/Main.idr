||| `idris2-browser-index`: the command line of the indexer.
|||
||| The options front ends rely on are specified in `doc/index-format.md`,
||| "Command line".
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Index.Main

import Data.String
import System
import System.File

import IdrisBrowser.Schema
import IdrisBrowser.Index.Update

%default covering

usage : String
usage = """
  usage: idris2-browser-index [--index-dir DIR] [--prefix DIR] (--update [--json] [--pretty] | --print-index-dir)
  """

data Command = Update | PrintIndexDir

record Args where
  constructor MkArgs
  command : Maybe Command
  indexDir : Maybe String
  prefixDir : Maybe String
  json : Bool
  pretty : Bool

parseArgs : Args -> List String -> Maybe Args
parseArgs a [] = Just a
parseArgs a ("--update" :: rest) = parseArgs ({ command := Just Update } a) rest
parseArgs a ("--print-index-dir" :: rest) = parseArgs ({ command := Just PrintIndexDir } a) rest
parseArgs a ("--json" :: rest) = parseArgs ({ json := True } a) rest
parseArgs a ("--pretty" :: rest) = parseArgs ({ pretty := True } a) rest
parseArgs a ("--index-dir" :: d :: rest) = parseArgs ({ indexDir := Just d } a) rest
parseArgs a ("--prefix" :: d :: rest) = parseArgs ({ prefixDir := Just d } a) rest
parseArgs _ _ = Nothing

main : IO ()
main = do
  _ :: args <- getArgs
    | [] => exitWith (ExitFailure 1)
  let Just (MkArgs (Just cmd) dir pfx json pretty) = parseArgs (MkArgs Nothing Nothing Nothing False False) args
    | _ => do
        ignore (fPutStrLn stderr usage)
        exitWith (ExitFailure 1)
  indexDir <- maybe defaultIndexDir pure dir
  case cmd of
    PrintIndexDir => putStrLn indexDir
    Update => do
      code <- update (MkOptions indexDir pfx json pretty)
      case code of
        0 => exitSuccess
        2 => exitWith (ExitFailure 2)
        _ => exitWith (ExitFailure 1)
