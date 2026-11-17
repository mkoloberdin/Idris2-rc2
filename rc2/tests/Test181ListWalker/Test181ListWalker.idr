module Main

import Data.List

-- Functions of the program that take a list apart and pass the rest only to one call of themselves
-- ("walkers", rc2/doc/list-divert.md): with --directive listfuse a chain feeds them without the
-- list being built. A function that reads the rest twice is left alone.

-- accumulates: a foldl of its own
sumSq : Int -> List Int -> Int
sumSq acc [] = acc
sumSq acc (x :: xs) = sumSq (acc + x * x) xs

-- builds a list: the recursive call is under a constructor
pairs : List Int -> List (Int, Int)
pairs [] = []
pairs (x :: xs) = (x, x * 10) :: pairs xs

-- the list is not the first parameter, and the others change
weigh : Int -> List Int -> Int -> Int
weigh k [] acc = acc + k
weigh k (x :: xs) acc = weigh (k + 1) xs (acc + k * x)

-- reads the rest twice: not a walker, left alone
twiceRest : List Int -> List Int
twiceRest [] = []
twiceRest (x :: xs) = x :: (twiceRest xs ++ xs)

-- two walkers that pass the rest to each other
evens : List Int -> List Int
odds : List Int -> List Int
evens [] = []
evens (x :: xs) = x :: odds xs
odds [] = []
odds (x :: xs) = (x * 2) :: evens xs

main : IO ()
main = do
  let xs : List Int = [1, 2, 3, 4, 5, 6, 7, 8]
  printLn (sumSq 0 (map (+ 1) (filter (> 2) xs)))
  printLn (pairs (map (* 2) xs))
  printLn (weigh 1 (filter (\x => x `mod` 2 == 0) xs) 0)
  printLn (twiceRest (map (+ 1) [1, 2, 3]))
  printLn (sumSq 0 (map (+ 1) (the (List Int) [])))
  -- intersperse passes its rest to mergeReplicate, a walker
  printLn (intersperse 0 (map (* 3) (filter (> 2) xs)))
  printLn (evens (map (+ 10) xs))
  printLn (odds (filter (\x => x `mod` 2 == 1) xs))
  -- zipWith, as rc2_zipWith, is a walker of its first list
  printLn (zipWith (+) (map (* 2) xs) [10, 20, 30])
  printLn (zip (filter (> 2) xs) [10, 20, 30])
