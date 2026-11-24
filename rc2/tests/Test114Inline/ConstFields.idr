module Test114Inline.ConstFields

-- Compiler.RC2.ConstFields (rc2/doc/dead-fields.md, "Constant constructors"):
-- the `Ord Key` dictionary reaches Data.SortedMap as one constant, and
-- SortedMap binds only some of its fields. `max` and `min` are defined here,
-- so they are functions of their own, named only by that constant; with
-- their fields unread they must be gone from the program. check.sh tests it.

import Data.SortedMap

data Key = K Int

Eq Key where
  K a == K b = a == b

Ord Key where
  compare (K a) (K b) = compare a b
  max (K a) (K b) = K (if a > b then a * 1000 + 7 else b * 1000 + 7)
  min (K a) (K b) = K (if a < b then a * 1000 + 9 else b * 1000 + 9)

export
run : IO ()
run = do
  let m = fromList [(K 3, "three"), (K 1, "one"), (K 2, "two")]
  putStrLn (show (lookup (K 2) m))
  putStrLn (show (map fst' (SortedMap.toList m)))
  where
    fst' : (Key, String) -> Int
    fst' (K k, _) = k
