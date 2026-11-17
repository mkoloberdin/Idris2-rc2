module Main

-- `--directive strictnative` (rc2/doc/native-type-inference.md's "The strict mode"): values whose type
-- depends on another value, where one branch only passes the value on, so no read contradicts the
-- Bool branch's. The default mode makes a `uint8_t` worker of each and segfaults (KNOWN-BUGS.md, #343).
--   text:    a Bool, a Nat or a String by the key; the Nat branch passes the value to a recursive function
--   boxText: the same behind a newtype, which upstream erases
--   run:     a pointer or a String by the key; the pointer branch passes it to a `%foreign`
--   showP:   a constructor field whose type depends on the field before it

%cg rc2 strictnative

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

tally : Nat -> String
tally Z = "."
tally (S k) = "+" ++ tally k

encode : (t : VT) -> Value t -> String
encode AFlag b = if b then "1" else "0"
encode ACount n = tally n
encode AText s = s

text : (k : Key) -> Value (vt k) -> String
text k = encode (vt k)

dflt : (k : Key) -> Value (vt k)
dflt Enable = True
dflt Size = 3
dflt Name = "hello"

data Box : VT -> Type where
  MkBox : Value t -> Box t

render : (t : VT) -> Box t -> String
render AFlag (MkBox b) = if b then "1" else "0"
render ACount (MkBox n) = tally n
render AText (MkBox s) = s

boxText : (k : Key) -> Box (vt k) -> String
boxText k = render (vt k)

boxDflt : (k : Key) -> Box (vt k)
boxDflt Enable = MkBox True
boxDflt Size = MkBox 3
boxDflt Name = MkBox "hello"

data PK = APtr | AStr

PV : PK -> Type
PV APtr = AnyPtr
PV AStr = String

%foreign "CExpr:(($1) == NULL ? 1 : 0)"
isNullPtr : AnyPtr -> Int

%foreign "CExpr:((void *)0)"
nullp : AnyPtr

use : (k : PK) -> PV k -> String
use APtr p = show (isNullPtr p)
use AStr s = s ++ "!"

run : (k : PK) -> PV k -> String
run k v = use k v

val : (k : PK) -> PV k
val APtr = nullp
val AStr = "str"

data P : Type where
  MkP : (k : Key) -> Value (vt k) -> P

showP : P -> String
showP (MkP Enable b) = if b then "1" else "0"
showP (MkP Size n) = tally n
showP (MkP Name s) = s

ps : List P
ps = [MkP Enable True, MkP Size 3, MkP Name "hello", MkP Enable False]

main : IO ()
main = do
  putStrLn (text Enable False)
  traverse_ (\k => putStrLn (text k (dflt k))) (the (List Key) [Enable, Size, Name])
  putStrLn (boxText Enable (MkBox False))
  traverse_ (\k => putStrLn (boxText k (boxDflt k))) (the (List Key) [Enable, Size, Name])
  putStrLn (run APtr nullp)
  traverse_ (\k => putStrLn (run k (val k))) (the (List PK) [APtr, AStr])
  traverse_ (putStrLn . showP) ps
