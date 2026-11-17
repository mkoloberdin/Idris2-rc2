module Main

-- A fold whose accumulator's type depends on an argument: `Dom o` is a Bool for `Promise` and a
-- Maybe for `Within`. The loop `foldl` becomes kept the accumulator as a uint8_t, from the Bool
-- branch's read, and the Within branch read fields out of that byte (gcc errors). A loop variable
-- is now made native only if no read of it wants another type and no branch takes it apart
-- (rc2/doc/native-type-inference.md's "Types that depend on a value").

data Order = Promise | Within

Dom : Order -> Type
Dom Promise = Bool
Dom Within = Maybe (List Nat)

joinAt : (o : Order) -> Dom o -> Dom o -> Dom o
joinAt Promise a b = a && b
joinAt Within (Just a) (Just b) = Just (a ++ b)
joinAt Within _ _ = Nothing

top : (o : Order) -> Dom o
top Promise = True
top Within = Just []

joinAll : (o : Order) -> List (Dom o) -> Dom o
joinAll o xs = foldl (joinAt o) (top o) xs

main : IO ()
main = do
  putStrLn (show (joinAll Promise [True, True, False]))
  putStrLn (show (joinAll Within [Just [1], Just [2, 3]]))
