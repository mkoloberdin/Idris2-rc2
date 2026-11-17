module Main

-- Data.Nat.isLTE and lte compare once (rc2/doc/nat-magic.md): the same results as upstream's
-- recursive definitions, the proof of a Yes included, which this counts at run time.

import Data.Nat
import Data.Fin

proofSize : LTE m n -> Nat
proofSize LTEZero = Z
proofSize (LTESucc p) = S (proofSize p)

describe : (m, n : Nat) -> String
describe m n = case isLTE m n of
                    Yes prf => "Yes " ++ show (proofSize prf)
                    No _ => "No"

finOf : Nat -> Nat -> String
finOf k n = case natToFin k n of
                 Just f => "Just " ++ show (finToNat f)
                 Nothing => "Nothing"

main : IO ()
main = do
  for_ (the (List (Nat, Nat)) [(0, 0), (0, 5), (3, 5), (5, 5), (6, 5), (5, 0), (4000, 4001), (4001, 4000)]) $ \(m, n) => do
    putStrLn (show m ++ " " ++ show n ++ ": " ++ describe m n ++ ", lte " ++ show (lte m n)
              ++ ", gte " ++ show (gte m n) ++ ", lt " ++ show (lt m n))
  putStrLn (finOf 0 1 ++ " " ++ finOf 1 1 ++ " " ++ finOf 79 80 ++ " " ++ finOf 80 80)
  putStrLn (case isLT 2 3 of Yes p => "isLT Yes " ++ show (proofSize p); No _ => "isLT No")
