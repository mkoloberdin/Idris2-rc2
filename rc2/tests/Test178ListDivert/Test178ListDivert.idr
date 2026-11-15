module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- `++`, `map`, `filter` and `mapMaybe` on lists: upstream's %transform rules make them
-- two-pass functions over an intermediate list (`tailRecAppend`, `mapTR`, ...), which
-- Compiler.RC2.ListDivert replaces by naive definitions that TRMC turns into one loop
-- (rc2/doc/list-divert.md) when `--directive listdivert` is given. check.sh builds that
-- variant and looks for the upstream helpers in its IR and for the filled holes of the
-- loops; its output is the same as this default build's.

import Data.List
import System

%noinline
half : Int -> Maybe Int
half n = if n `mod` 2 == 0 then Just (n `div` 2) else Nothing

main : IO ()
main = do
  args <- getArgs
  let k = cast (length args)
  let xs = [k .. k + 9]
  let ys = map (* 3) xs ++ filter (\x => x `mod` 3 == 0) [k + 10 .. k + 30]
  printLn ys
  printLn (mapMaybe half ys)
  printLn (length (xs ++ ys ++ xs))
  printLn (sum (map (+ 1) (filter (> 5) (mapMaybe half [1 .. 100000 + k]))))
