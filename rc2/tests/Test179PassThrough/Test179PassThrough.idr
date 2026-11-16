||| A wrapper that only passes a call's result on is spliced at every call (here
||| `errno`, `let v = prim__errno w; v`), and a `%foreign` wrapper whose every
||| call was inlined is not emitted (here the `prim__SIGCONT` of `SIGCONT`).
module Main

import System.Posix.Errno
import System.Posix.Signal

check : Int32 -> IO (Either Errno Int32)
check r = checkNonNeg r

-- errno itself is not printed: what a process has left in it differs from one machine to another
main : IO ()
main = do
  a <- errno
  b <- errno
  c <- check 5
  d <- check (-1)
  printLn (case (a, b) of (MkErrno x, MkErrno y) => x >= 0 && y >= 0)
  printLn c
  putStrLn (case d of Left _ => "Left"; Right _ => "Right")
  printLn (SIGCONT == SIGCONT)
