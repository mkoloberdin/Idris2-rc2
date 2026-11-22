module Main

-- A value whose type depends on another value (`Value (vt k)`: a Bool, a Nat or a String by the key) in the
-- default build: it is held natively, and left out of the reference counting, only on the evidence of its
-- declared type or of a use on every path (rc2/doc/native-type-inference.md's "The default: a use on every
-- path"). Each section segfaulted before:
--   PassedOn        the value is only passed on, kept in a dependent pair or a record, returned (#343's shape 2)
--   Lambda          it is a lambda's argument or capture: the lifted lambda has no declared type
--   CaseCounted     one branch reads it with a constant `case`, another duplicates it as a String
--   OperandCounted  one branch reads it with a primitive op or a comparison, another duplicates it

import Test188DependentEveryPath.PassedOn
import Test188DependentEveryPath.Lambda
import Test188DependentEveryPath.CaseCounted
import Test188DependentEveryPath.OperandCounted

main : IO ()
main = do
  PassedOn.run
  Lambda.run
  CaseCounted.run
  OperandCounted.run
