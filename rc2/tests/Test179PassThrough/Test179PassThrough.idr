||| A wrapper that only passes a call's result on is spliced at every call (here
||| `errno`, `let v = prim__errno w; v`), and a `%foreign` wrapper whose every
||| call was inlined is not emitted (here the `prim__SIGCONT` of `SIGCONT`).
module Main

import System.Posix.Errno
import System.Posix.Signal

check : Int32 -> IO (Either Errno Int32)
check r = checkNonNeg r

main : IO ()
main = do
  a <- errno
  b <- errno
  c <- check 5
  d <- check (-1)
  printLn (a, b, c, d)
  printLn (SIGCONT == SIGCONT)
