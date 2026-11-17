module Main

-- A value that is a pointer for one key and a String for another: the pointer branch passes it to a
-- `%foreign` pointer parameter, which made it a `void *` worker parameter, and the String branch then
-- appended to that pointer (a segfault). A pointer is no primitive's operand, so a typed read of the
-- value now keeps it boxed (rc2/doc/native-type-inference.md's "Types that depend on a value").

data K = APtr | AStr

V : K -> Type
V APtr = AnyPtr
V AStr = String

%foreign "CExpr:(($1) == NULL ? 1 : 0)"
isNullPtr : AnyPtr -> Int

%foreign "CExpr:((void *)0)"
nullp : AnyPtr

use : (k : K) -> V k -> String
use APtr p = show (isNullPtr p)
use AStr s = s ++ "!"

run : (k : K) -> V k -> String
run k v = use k v

val : (k : K) -> V k
val APtr = nullp
val AStr = "str"

main : IO ()
main = do
  putStrLn (run APtr nullp)
  traverse_ (\k => putStrLn (run k (val k))) [APtr, AStr]
