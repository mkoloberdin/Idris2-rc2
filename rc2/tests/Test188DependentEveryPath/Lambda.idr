module Test188DependentEveryPath.Lambda

-- The value of a stuck type is a lambda's argument: the lifted lambda has no declared type at all.

data VT = AFlag | ACount | AText

Value : VT -> Type
Value AFlag = Bool
Value ACount = Nat
Value AText = String

tally : Nat -> String
tally Z = "."
tally (S k) = "+" ++ tally k

%inline
encode : (t : VT) -> Value t -> String
encode AFlag b = if b then "1" else "0"
encode ACount n = tally n
encode AText s = s

vals : (t : VT) -> List (Value t)
vals AFlag = [False, True]
vals ACount = [0, 3]
vals AText = ["hello", ""]

-- the lambda takes the value; `encode` is inlined into it
texts : (t : VT) -> List String
texts t = map (\v => encode t v ++ "!") (vals t)

-- the lambda captures the value
later : (t : VT) -> Value t -> () -> String
later t v = \u => encode t v ++ "?"

export
run : IO ()
run = do
  traverse_ (\t => traverse_ putStrLn (texts t)) [AFlag, ACount, AText]
  traverse_ (\f => putStrLn (f ())) [later AFlag True, later ACount 2, later AText "text"]
