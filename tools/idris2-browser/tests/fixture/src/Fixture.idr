||| A package for the indexer's tests: one definition of every kind.
module Fixture

import public Fixture.Shapes
import Data.List

||| A colour, with a non-ASCII doc: 色 and 🐈 survive the index.
public export
data Colour = Red | Green | Blue

||| A point in the plane.
public export
record Point where
  constructor MkPoint
  ||| The horizontal coordinate.
  x : Int
  y : Int

||| Things that have a name.
public export
interface Named a where
  ||| The name of a value.
  name : a -> String

export
Named Colour where
  name Red = "red"
  name Green = "green"
  name Blue = "blue"

||| Total and documented.
total
export
double : Nat -> Nat
double n = n + n

export
undocumented : List Int -> Int
undocumented = sum

||| Private, with "quotes", a \ backslash, a tab	and
||| a second line.
private
hidden : Int
hidden = 1

||| Covering, not checked for termination.
covering
export
loop : Int -> Int
loop n = loop n

||| Partial: a missing case.
partial
export
firstOf : List a -> a
firstOf (x :: _) = x

%foreign "C:abs,libc 6"
export
cAbs : Int -> Int
