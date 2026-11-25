module Test114Inline.ShareSubtrees

-- Compiler.RC2.ShareSubtrees (rc2/doc/shared-subtrees.md): `pairUp` falls
-- back to its last clause in every alt of its first `case` that does not
-- match, and the case tree holds that clause once for each of them. The
-- copies must be one function, called from each place. check.sh tests it.

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

export
run : IO ()
run = do
  putStrLn (pairUp (Sq 2) (Sq 3))
  putStrLn (pairUp (Sq 2) (Rect 3 4))
  putStrLn (pairUp (Rect 1 2) (Tri 3 4 5))
  putStrLn (pairUp (Tri 1 2 3) Dot)
  putStrLn (pairUp Dot (Sq 9))
