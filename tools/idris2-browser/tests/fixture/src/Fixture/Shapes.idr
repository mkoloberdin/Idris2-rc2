module Fixture.Shapes

public export
data Shape = Circle Double | Square Double

export
area : Shape -> Double
area (Circle r) = 3.14159 * r * r
area (Square s) = s * s

export infixl 6 |+|

||| An operator of this module's own fixity.
export
(|+|) : Shape -> Shape -> Double
a |+| b = area a + area b
