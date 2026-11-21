module Test188DependentEveryPath.OperandCounted

import Data.String

-- As repro-rc, but the branch that knows the value is small reads it with a primitive op or a comparison
-- (a Bits8, a Char), not with a constant `case`.

data VT = AByte | ALetter | AText

Value : VT -> Type
Value AByte = Bits8
Value ALetter = Char
Value AText = String

both : (t : VT) -> Value t -> (Value t, Value t)
both AByte b = (b + 1, b)
both ALetter c = if c == 'x' then ('y', c) else (c, 'x')
both AText s = (s, s)

encode : (t : VT) -> Value t -> String
encode AByte b = show b
encode ALetter c = singleton c
encode AText s = s

build : Nat -> String
build n = replicate n 'x' ++ show n

shown : (t : VT) -> Value t -> String
shown t v = let (a, b) = both t v in encode t a ++ "/" ++ encode t b

loop : Nat -> Nat -> Nat
loop Z acc = acc
loop (S k) acc = loop k (acc + length (shown AText (build (S k))) + length (shown AByte (cast k)) + length (shown ALetter (if k > 3 then 'x' else 'q')))

export
run : IO ()
run = do
  putStrLn (shown AByte 41)
  putStrLn (shown ALetter 'x')
  putStrLn (shown AText (build 5))
  printLn (loop 2000 0)
