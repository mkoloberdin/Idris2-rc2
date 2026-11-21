module Test188DependentEveryPath.PassedOn

import Data.List
import Data.String

-- A value whose type is a large elimination over a variable key: `Setting k` is a Bool, a Nat or a String.
-- Every use below only passes the value on, takes it out of a dependent pair, or reads it in the branch
-- that knows the key: none of them fixes one representation.

data VT = AFlag | ACount | AText

Value : VT -> Type
Value AFlag = Bool
Value ACount = Nat
Value AText = String

data Key = Enable | Hide | Size | Width | Name | Mail

vt : Key -> VT
vt Enable = AFlag
vt Hide = AFlag
vt Size = ACount
vt Width = ACount
vt Name = AText
vt Mail = AText

Setting : Key -> Type
Setting k = Value (vt k)

keys : List Key
keys = [Enable, Hide, Size, Width, Name, Mail]

dflt : (k : Key) -> Setting k
dflt Enable = False
dflt Hide = True
dflt Size = 24
dflt Width = 4
dflt Name = "a name"
dflt Mail = ""

digits : Nat -> String
digits Z = "z"
digits (S k) = "s" ++ digits k

encode : (t : VT) -> Value t -> String
encode AFlag b = if b then "1" else "0"
encode ACount n = digits n
encode AText s = s

-- 1. the site's shape: the value is only passed on
text : (k : Key) -> Setting k -> String
text k = encode (vt k)

-- 2. read back by the key
decode : (t : VT) -> String -> Value t
decode AFlag s = s == "1"
decode ACount s = cast s
decode AText s = s

get : (k : Key) -> Maybe String -> Setting k
get k Nothing = dflt k
get k (Just s) = decode (vt k) s

-- 3. a dependent pair: the second field's type is stuck on the first
pairs : List (k : Key ** Setting k)
pairs = map (\k => (k ** dflt k)) keys

showPair : (k : Key ** Setting k) -> String
showPair (k ** v) = text k v

-- 4. a record with a dependent field, and a fold whose accumulator is a string
record Held where
  constructor MkHeld
  key : Key
  value : Setting key

held : List Held
held = [MkHeld Enable True, MkHeld Size 7, MkHeld Name "held", MkHeld Hide False]

heldText : Held -> String
heldText h = text h.key h.value

-- 5. a result of a stuck type, read in the branch that knows the key
twice : (k : Key) -> Setting k -> Setting k
twice Enable b = not b
twice Hide b = b
twice Size n = n + n
twice Width n = n * 2
twice Name s = s ++ s
twice Mail s = s

-- 6. a polymorphic function instantiated at the stuck type
pick : Bool -> a -> a -> a
pick True x _ = x
pick False _ y = y

export
run : IO ()
run = do
  putStrLn (text Enable False)
  putStrLn (text Size 3)
  traverse_ (\k => putStrLn (text k (dflt k))) keys
  traverse_ (\k => putStrLn (text k (get k Nothing))) keys
  putStrLn (text Enable (get Enable (Just "1")))
  putStrLn (text Width (get Width (Just "5")))
  putStrLn (text Mail (get Mail (Just "a@b")))
  traverse_ (putStrLn . showPair) pairs
  putStrLn (concat (intersperse "," (map heldText held)))
  traverse_ (\k => putStrLn (text k (twice k (dflt k)))) keys
  traverse_ (\k => putStrLn (text k (pick (length (text k (dflt k)) > 1) (dflt k) (twice k (dflt k))))) keys
