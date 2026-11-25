module Test114Inline.ShareSubtrees

-- Compiler.RC2.ShareSubtrees (rc2/doc/shared-subtrees.md): `pairUp` falls
-- back to its last clause in every alt of its first `case` that does not
-- match, and the case tree holds that clause once for each of them. The
-- copies must be one function, called from each place; so must `score`'s
-- three alts, which read a different field each. check.sh tests both.

data Shape = Sq Int | Rect Int Int | Tri Int Int Int | Dot

area : Shape -> Int
area (Sq a) = a * a
area (Rect a b) = a * b
area (Tri a b c) = a + b + c
area Dot = 0

export
pairUp : Shape -> Shape -> String
pairUp (Sq a) (Sq b) = "squares " ++ show (a + b)
pairUp (Rect a b) (Rect c d) = "rects " ++ show (a * d - b * c)
pairUp (Tri a _ _) (Tri b _ _) = "tris " ++ show (a - b)
pairUp p q =
  let s = area p * 31 + area q * 17
      t = if s > 100 then s `div` 3 else s * 5 + 1
  in "mixed " ++ show s ++ "/" ++ show t ++ "/" ++ show (s + t * 2)

-- The same computation over a different field in each alt: one function,
-- called with that field.
export
score : Shape -> Int
score (Sq a) = let s = a * 4099 + 23
                   t = if s > 100 then s `div` 3 else s * 5 + 1
               in s + t * 2 + (s `mod` 11) * t + (t `mod` 13) * s + s * t * 3 - (s `div` 17)
score (Rect _ b) = let s = b * 4099 + 23
                       t = if s > 100 then s `div` 3 else s * 5 + 1
                   in s + t * 2 + (s `mod` 11) * t + (t `mod` 13) * s + s * t * 3 - (s `div` 17)
score (Tri _ _ c) = let s = c * 4099 + 23
                        t = if s > 100 then s `div` 3 else s * 5 + 1
                    in s + t * 2 + (s `mod` 11) * t + (t `mod` 13) * s + s * t * 3 - (s `div` 17)
score Dot = 0

export
run : IO ()
run = do
  putStrLn (pairUp (Sq 2) (Sq 3))
  putStrLn (pairUp (Sq 2) (Rect 3 4))
  putStrLn (pairUp (Rect 1 2) (Tri 3 4 5))
  putStrLn (pairUp (Tri 1 2 3) Dot)
  putStrLn (pairUp Dot (Sq 9))
  printLn (map score [Sq 2, Rect 1 3, Tri 1 2 5, Dot])
