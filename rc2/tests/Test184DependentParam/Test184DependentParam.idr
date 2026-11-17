module Main

-- A parameter whose type depends on another argument (`Value (vt k)`: a Bool, a Nat or a String) holds a
-- different primitive in each branch of the case on that argument. The constant-key call made DualABI
-- promote it to the one branch's native type (uint8_t, read as a Bool), and the run-time-key calls then
-- handed the Nat and the String branches a byte: a segfault. A promotion now stands only if every typed
-- read of the parameter agrees with it (`DualABI.primReadTypes`).

data VT = AFlag | ACount | AText

Value : VT -> Type
Value AFlag = Bool
Value ACount = Nat
Value AText = String

data Key = Enable | Size | Name

vt : Key -> VT
vt Enable = AFlag
vt Size = ACount
vt Name = AText

encode : (t : VT) -> Value t -> String
encode AFlag b = if b then "1" else "0"
encode ACount n = show n
encode AText s = s

text : (k : Key) -> Value (vt k) -> String
text k = encode (vt k)

dflt : (k : Key) -> Value (vt k)
dflt Enable = True
dflt Size = 24
dflt Name = "hello"

main : IO ()
main = do
  putStrLn (text Enable False)
  traverse_ (\k => putStrLn (text k (dflt k))) [Enable, Size, Name]
