module Main

-- Compiler.RC2.DeadFields (rc2/doc/dead-fields.md): a result taken apart at once, some fields
-- unread, comes from a copy that does not make them. myLTE's copy makes no proof and is a loop;
-- stats's copy does not count; the field noisy leaves out is made by an IO action, which still runs;
-- a field naming a CAF that prints is not left out.

import Data.Nat

%cg rc2 deadfields

-- upstream's isLTE under another name: a recursion that rebuilds its proof
myLTE : (m, n : Nat) -> Dec (LTE m n)
myLTE Z n = Yes LTEZero
myLTE (S k) Z = No succNotLTEzero
myLTE (S k) (S j) = case myLTE k j of
                         No contra => No (contra . fromLteSucc)
                         Yes prf => Yes (LTESucc prf)

within : Nat -> Nat -> Bool
within k n = case myLTE k n of
                  Yes _ => True
                  No _ => False

-- a pair of which the caller reads one half
stats : List Int -> (Int, Int)
stats [] = (0, 0)
stats (x :: xs) = case stats xs of
                       (s, c) => (s + x, c + 1)

total' : List Int -> Int
total' xs = case stats xs of (s, _) => s

-- the field left out is made by an IO action; the action still runs
noisy : Int -> (Int, Int)
noisy x = let y = unsafePerformIO (do putStrLn ("side effect for " ++ show x); pure (x * 2))
          in (x + 1, y)

firstOnly : Int -> Int
firstOnly x = case noisy x of (a, _) => a

-- a CAF whose first evaluation prints: naming it in a field evaluates it, so that field stays
noisyCaf : Int
noisyCaf = unsafePerformIO (do putStrLn "the CAF is evaluated"; pure 7)

countCaf : Nat -> (Int, Int)
countCaf Z = (0, noisyCaf)
countCaf (S k) = case countCaf k of (a, b) => (a + 1, b)

cafFirst : Nat -> Int
cafFirst n = case countCaf n of (a, _) => a

main : IO ()
main = do
  printLn (map (\k => within k 50) [0, 49, 50, 51, 100])
  printLn (within 3000 3001)
  printLn (total' [1 .. 1000])
  printLn (firstOnly 20)
  printLn (cafFirst 5)
