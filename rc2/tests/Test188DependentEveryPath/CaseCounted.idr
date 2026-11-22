module Test188DependentEveryPath.CaseCounted

import Data.String

-- Reference counting, not unboxing: one branch reads the value with a constant `case` (a Bool), another
-- duplicates or drops it as a heap value (a String built at run time).

data VT = AFlag | ACount | AText

Value : VT -> Type
Value AFlag = Bool
Value ACount = Nat
Value AText = String

both : (t : VT) -> Value t -> (Value t, Value t)
both AFlag b = if b then (False, True) else (True, False)
both ACount n = (n, n)
both AText s = (s, s)

keep : (t : VT) -> Value t -> Value t -> Value t
keep AFlag a b = if a then b else a
keep ACount a b = a
keep AText a b = b

encode : (t : VT) -> Value t -> String
encode AFlag b = if b then "1" else "0"
encode ACount n = show n
encode AText s = s

build : Nat -> String
build n = replicate n 'x' ++ show n

shown : (t : VT) -> Value t -> String
shown t v = let (a, b) = both t v
                c = keep t a b
             in encode t a ++ "/" ++ encode t b ++ "/" ++ encode t c

loop : Nat -> Nat -> Nat
loop Z acc = acc
loop (S k) acc = loop k (acc + length (shown AText (build (S k))) + length (shown ACount (k * 1000003)) + length (shown AFlag (k > 3)))

export
run : IO ()
run = do
  putStrLn (shown AFlag True)
  putStrLn (shown ACount 12345678901234567890)
  putStrLn (shown AText (build 5))
  printLn (loop 2000 0)
