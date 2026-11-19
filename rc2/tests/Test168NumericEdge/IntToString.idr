module Test168NumericEdge.IntToString

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- `show` of every fixed-width integer type at its bounds, at zero and at -1:
-- the runtime writes the digits itself (idris2rc2_decimalString, numeric.c),
-- and minBound has no positive counterpart in its own type. The values come
-- from the command line, so nothing folds.

import System

%default total

line : Show a => String -> List a -> IO ()
line name xs = putStrLn (name ++ ": " ++ show xs)

export
run : IO ()
run = do
  args <- getArgs
  let n : Integer = cast (length args) - 1
  line "Int" (the (List Int) (map fromInteger [-9223372036854775808 + n, 9223372036854775807 + n, n, n - 1, 10 + n]))
  line "Int64" (the (List Int64) (map fromInteger [-9223372036854775808 + n, 9223372036854775807 + n, n, n - 1, 10 + n]))
  line "Int32" (the (List Int32) (map fromInteger [-2147483648 + n, 2147483647 + n, n, n - 1, 10 + n]))
  line "Int16" (the (List Int16) (map fromInteger [-32768 + n, 32767 + n, n, n - 1, 10 + n]))
  line "Int8" (the (List Int8) (map fromInteger [-128 + n, 127 + n, n, n - 1, 10 + n]))
  line "Bits64" (the (List Bits64) (map fromInteger [18446744073709551615 + n, 9223372036854775808 + n, n, 10 + n]))
  line "Bits32" (the (List Bits32) (map fromInteger [4294967295 + n, n, 10 + n]))
  line "Bits16" (the (List Bits16) (map fromInteger [65535 + n, n, 10 + n]))
  line "Bits8" (the (List Bits8) (map fromInteger [255 + n, n, 10 + n]))
  let i : Int = fromInteger (-9223372036854775808 + n)
  putStrLn ("native Int: " ++ show i ++ " " ++ show (i + 1) ++ " " ++ show (cast {to = Int} n))
  let i64 : Int64 = fromInteger (-9223372036854775808 + n)
  let b64 : Bits64 = fromInteger (18446744073709551615 + n)
  putStrLn ("native Int64, Bits64: " ++ show i64 ++ " " ++ show (i64 + 1) ++ " " ++ show b64 ++ " " ++ show (b64 - 1))
