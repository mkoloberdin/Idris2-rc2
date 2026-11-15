module Main

-- Appends two 500000-element lists and sums the result, forty times: upstream's
-- `++` is `reverseOnto ys (reverse xs)`, two passes and an intermediate list, where
-- rc2's TRMC makes the naive definition one pass under --directive listdivert
-- (rc2/doc/list-divert.md).
go : Int -> Int -> Int
go 0 acc = acc
go n acc = go (n - 1) (acc + sum ([1 .. 500000] ++ [n .. n + 500000]))

main : IO ()
main = printLn (go 40 0)
