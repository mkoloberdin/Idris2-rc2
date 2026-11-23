||| File-system helpers of the indexer: times, atomic writes, the lock and
||| directory walks.
|||
||| The rules they implement (whole-file replacement by rename, the `.lock/`
||| directory with a `pid` file) are the writer's side of
||| `doc/index-format.md`.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.Index.Files

import Data.Bits
import Data.Either
import Data.List1
import Data.List
import Data.String
import System
import System.Clock
import System.Directory
import System.File

%default covering

-------------------------------------------------------------------------------
-- Times

||| Seconds since the epoch as RFC 3339 UTC, e.g. `2026-11-23T10:00:00Z`.
export
rfc3339 : Integer -> String
rfc3339 t =
  let days = t `div` 86400
      secs = t `mod` 86400
      (y, m, d) = civil days
   in "\{show y}-\{pad m}-\{pad d}T\{pad (secs `div` 3600)}:\{pad ((secs `mod` 3600) `div` 60)}:\{pad (secs `mod` 60)}Z"
  where
    pad : Integer -> String
    pad n = if n < 10 then "0" ++ show n else show n

    -- Howard Hinnant's `civil_from_days`.
    civil : Integer -> (Integer, Integer, Integer)
    civil z0 =
      let z : Integer = z0 + 719468
          era : Integer = z `div` 146097
          doe : Integer = z - era * 146097
          yoe : Integer = (doe - doe `div` 1460 + doe `div` 36524 - doe `div` 146096) `div` 365
          doy : Integer = doe - (365 * yoe + yoe `div` 4 - yoe `div` 100)
          mp : Integer = (5 * doy + 2) `div` 153
          d : Integer = doy - (153 * mp + 2) `div` 5 + 1
          m : Integer = if mp < 10 then mp + 3 else mp - 9
       in (yoe + era * 400 + (if m <= 2 then 1 else 0), m, d)

export
now : IO Integer
now = seconds <$> clockTime UTC

||| Size and modification time (seconds) of a file.
export
fileStat : String -> IO (Maybe (Integer, Integer))
fileStat path = do
  Right h <- openFile path Read
    | Left _ => pure Nothing
  sz <- fileSize h
  mt <- fileModifiedTime h
  closeFile h
  pure [| MkPair (cast <$> eitherToMaybe sz) (cast <$> eitherToMaybe mt) |]

-------------------------------------------------------------------------------
-- Writing

%foreign "C:rename,libc 6"
prim__rename : String -> String -> PrimIO Int

||| Replace `path` as a whole: readers see the old file or the new one.
export
writeAtomic : (path : String) -> (contents : String) -> IO (Either String ())
writeAtomic path contents = do
  pid <- getPID
  let tmp = path ++ ".tmp." ++ show pid
  Right () <- writeFile tmp contents
    | Left err => do
        ignore (removeFile tmp)
        pure (Left "\{tmp}: \{show err}")
  r <- primIO (prim__rename tmp path)
  if r == 0
    then pure (Right ())
    else do
      ignore (removeFile tmp)
      pure (Left "\{path}: rename failed")

||| `mkdir -p`.
export
createDirs : String -> IO ()
createDirs dir = go (pathPrefixes dir)
  where
    pathPrefixes : String -> List String
    pathPrefixes d =
      let parts = forget (split (== '/') d)
          lead = if isPrefixOf "/" d then "/" else ""
       in drop 1 $ map (\ps => lead ++ joinBy "/" ps) (inits (filter (/= "") parts))

    go : List String -> IO ()
    go [] = pure ()
    go (p :: ps) = do
      ignore (createDir p)
      go ps

-------------------------------------------------------------------------------
-- Directories

||| The entries of a directory, without `.` and `..`; empty if it can't be read.
export
entries : String -> IO (List String)
entries dir = do
  Right es <- listDir dir
    | Left _ => pure []
  pure (sort (filter (\e => e /= "." && e /= "..") es))

export
isDirectory : String -> IO Bool
isDirectory path = do
  Right d <- openDir path
    | Left _ => pure False
  closeDir d
  pure True

||| `rm -r`.
export
removeTree : String -> IO ()
removeTree path = do
  Left _ <- removeFile path
    | Right () => pure ()
  es <- entries path
  traverse_ (\e => removeTree (path ++ "/" ++ e)) es
  removeDir path

-------------------------------------------------------------------------------
-- The lock

||| How taking the lock went.
public export
data LockResult = Locked | HeldBy Int | LockFailed String

||| Take `<dir>/.lock/`, taking over a lock whose process is gone (looked up
||| in `/proc`, so on Linux only).
|||
||| The lock is a directory made with its `pid` file inside and renamed into
||| place, so a lock that can be seen always names its holder. A stale one is
||| renamed out of the way first: of two takers only one rename succeeds.
export
takeLock : (indexDir : String) -> IO LockResult
takeLock indexDir = do
  pid <- getPID
  let lockDir = indexDir ++ "/.lock"
      mine = lockDir ++ "." ++ show pid
  removeTree mine
  Right () <- createDir mine
    | Left err => pure (LockFailed "\{mine}: \{show err}")
  Right () <- writeFile (mine ++ "/pid") (show pid ++ "\n")
    | Left err => do
        removeTree mine
        pure (LockFailed "\{mine}: \{show err}")
  res <- attempt pid lockDir mine (the Nat 3)
  removeTree mine
  pure res
  where
    attempt : Int -> (lockDir, mine : String) -> Nat -> IO LockResult
    attempt _ lockDir _ Z = pure (LockFailed "\{lockDir}: could not be taken")
    attempt pid lockDir mine (S k) = do
      0 <- primIO (prim__rename mine lockDir)
        | _ => do
            holder <- either (const Nothing) (parsePositive . trim) <$> readFile (lockDir ++ "/pid")
            case holder of
              Just h => if !(isDirectory ("/proc/" ++ show h))
                then pure (HeldBy h)
                else takeOver
              Nothing => takeOver
      pure Locked
      where
        takeOver : IO LockResult
        takeOver = do
          let stale = lockDir ++ ".stale." ++ show pid
          _ <- primIO (prim__rename lockDir stale)
          removeTree stale
          attempt pid lockDir mine k

export
releaseLock : (indexDir : String) -> IO ()
releaseLock indexDir = removeTree (indexDir ++ "/.lock")

-------------------------------------------------------------------------------
-- Keys

||| The first 8 hex digits of FNV-1a over the code points of a string.
export
hash8 : String -> String
hash8 s = hex (foldl step 0x811c9dc5 (unpack s))
  where
    step : Bits32 -> Char -> Bits32
    step h c = (h `xor` cast (ord c)) * 0x01000193

    hexDigit : Integer -> Char
    hexDigit d = if d < 10 then chr (cast d + ord '0') else chr (cast d - 10 + ord 'a')

    hex : Bits32 -> String
    hex h = let n = the Integer (cast h)
             in pack (map (\i => hexDigit ((n `div` pow16 i) `mod` 16)) [7, 6, 5, 4, 3, 2, 1, 0])
      where
        pow16 : Nat -> Integer
        pow16 i = product (replicate i 16)
