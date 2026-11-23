||| Rendering and parsing JSON for the index.
|||
||| The value type is `contrib`'s `Language.JSON.Data.JSON`. Its own renderer
||| escapes every non-ASCII character through a `Bits16` (which breaks
||| characters outside the BMP) and builds the text with `concatMap`, so this
||| module has its own renderer, which keeps UTF-8 as it is, and a parser to
||| go with it. Both are linear in the size of the text.
|||
||| This module was licensed by BSD3. see LICENSE file for detail.
module IdrisBrowser.JSON

import public Language.JSON.Data

import Data.List
import Data.String
import System.File

%default total

-------------------------------------------------------------------------------
-- Rendering

hexDigit : Int -> Char
hexDigit d = if d < 10 then chr (ord '0' + d) else chr (ord 'a' + d - 10)

escape : Char -> List String -> List String
escape '"' acc = "\\\"" :: acc
escape '\\' acc = "\\\\" :: acc
escape '\n' acc = "\\n" :: acc
escape '\r' acc = "\\r" :: acc
escape '\t' acc = "\\t" :: acc
escape c acc =
  if ord c < 0x20
    then pack ['\\', 'u', '0', '0', hexDigit (ord c `div` 16), hexDigit (ord c `mod` 16)] :: acc
    else cast c :: acc

renderString : String -> List String -> List String
renderString s acc = "\"" :: foldr escape ("\"" :: acc) (unpack s)

renderNumber : Double -> String
renderNumber x =
  -- Counts and sizes are whole numbers; print them without Idris' ".0".
  if x == floor x && abs x < 9007199254740992.0
    then show (the Integer (cast x))
    else show x

mutual
  renderTo : JSON -> List String -> List String
  renderTo JNull acc = "null" :: acc
  renderTo (JBoolean b) acc = (if b then "true" else "false") :: acc
  renderTo (JNumber x) acc = renderNumber x :: acc
  renderTo (JString s) acc = renderString s acc
  renderTo (JArray xs) acc = "[" :: renderItems xs ("]" :: acc)
  renderTo (JObject kvs) acc = "{" :: renderFields kvs ("}" :: acc)

  renderItems : List JSON -> List String -> List String
  renderItems [] acc = acc
  renderItems [x] acc = renderTo x acc
  renderItems (x :: xs) acc = renderTo x ("," :: renderItems xs acc)

  renderFields : List (String, JSON) -> List String -> List String
  renderFields [] acc = acc
  renderFields [(k, v)] acc = renderString k (":" :: renderTo v acc)
  renderFields ((k, v) :: kvs) acc = renderString k (":" :: renderTo v ("," :: renderFields kvs acc))

||| The text of a value, without whitespace.
export
render : JSON -> String
render j = fastConcat (renderTo j [])

-- Arrays of scalars stay on one line, so a `names` row or a position is one
-- line of a diff.
mutual
  prettyTo : String -> JSON -> List String -> List String
  prettyTo ind (JArray xs) acc =
    if all isScalar xs || isNil xs
      then renderTo (JArray xs) acc
      else "[\n" :: prettyItems (ind ++ "  ") xs ("\n" :: ind :: "]" :: acc)
  prettyTo ind (JObject []) acc = "{}" :: acc
  prettyTo ind (JObject kvs) acc = "{\n" :: prettyFields (ind ++ "  ") kvs ("\n" :: ind :: "}" :: acc)
  prettyTo _ j acc = renderTo j acc

  prettyItems : String -> List JSON -> List String -> List String
  prettyItems _ [] acc = acc
  prettyItems ind [x] acc = ind :: prettyTo ind x acc
  prettyItems ind (x :: xs) acc = ind :: prettyTo ind x (",\n" :: prettyItems ind xs acc)

  prettyFields : String -> List (String, JSON) -> List String -> List String
  prettyFields _ [] acc = acc
  prettyFields ind [(k, v)] acc = ind :: renderString k (": " :: prettyTo ind v acc)
  prettyFields ind ((k, v) :: kvs) acc =
    ind :: renderString k (": " :: prettyTo ind v (",\n" :: prettyFields ind kvs acc))

  isScalar : JSON -> Bool
  isScalar (JArray _) = False
  isScalar (JObject _) = False
  isScalar _ = True

||| The text of a value, indented by two spaces per level.
export
renderPretty : JSON -> String
renderPretty j = fastConcat (prettyTo "" j ["\n"])

-------------------------------------------------------------------------------
-- Parsing

skipWs : List Char -> List Char
skipWs (c :: cs) = if c == ' ' || c == '\n' || c == '\r' || c == '\t' then skipWs cs else c :: cs
skipWs [] = []

hexValue : Char -> Maybe Int
hexValue c =
  if c >= '0' && c <= '9' then Just (ord c - ord '0')
  else if c >= 'a' && c <= 'f' then Just (ord c - ord 'a' + 10)
  else if c >= 'A' && c <= 'F' then Just (ord c - ord 'A' + 10)
  else Nothing

hex4 : List Char -> Maybe (Int, List Char)
hex4 (a :: b :: c :: d :: rest) = do
  [w, x, y, z] <- traverse hexValue [a, b, c, d]
    | _ => Nothing
  pure (((w * 16 + x) * 16 + y) * 16 + z, rest)
hex4 _ = Nothing

-- The characters of a string after its opening quote, reversed, and what
-- follows the closing quote.
parseStringBody : List Char -> List Char -> Maybe (List Char, List Char)
parseStringBody acc ('"' :: rest) = Just (acc, rest)
parseStringBody acc ('\\' :: c :: rest) = case c of
  '"' => parseStringBody ('"' :: acc) rest
  '\\' => parseStringBody ('\\' :: acc) rest
  '/' => parseStringBody ('/' :: acc) rest
  'b' => parseStringBody ('\b' :: acc) rest
  'f' => parseStringBody ('\f' :: acc) rest
  'n' => parseStringBody ('\n' :: acc) rest
  'r' => parseStringBody ('\r' :: acc) rest
  't' => parseStringBody ('\t' :: acc) rest
  'u' => do
    (hi, rest') <- hex4 rest
    if hi >= 0xD800 && hi < 0xDC00
      then case rest' of
        '\\' :: 'u' :: more => do
          (lo, rest'') <- hex4 more
          True <- Just (lo >= 0xDC00 && lo < 0xE000)
            | False => Nothing
          let cp = 0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)
          parseStringBody (chr cp :: acc) (assert_smaller rest rest'')
        _ => Nothing
      else if hi >= 0xDC00 && hi < 0xE000 then Nothing
      else parseStringBody (chr hi :: acc) (assert_smaller rest rest')
  _ => Nothing
parseStringBody acc (c :: rest) = parseStringBody (c :: acc) rest
parseStringBody _ [] = Nothing

parseNumber : List Char -> Maybe (Double, List Char)
parseNumber cs =
  let (num, rest) = span isNumChar cs
   in case parseDouble (pack num) of
        Just d => Just (d, rest)
        Nothing => Nothing
  where
    isNumChar : Char -> Bool
    isNumChar c = isDigit c || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E'

mutual
  covering
  parseValue : List Char -> Maybe (JSON, List Char)
  parseValue cs = case skipWs cs of
    '{' :: rest => parseObject [] (skipWs rest)
    '[' :: rest => parseArray [] (skipWs rest)
    '"' :: rest => do
      (s, rest') <- parseStringBody [] rest
      pure (JString (pack (reverse s)), rest')
    't' :: 'r' :: 'u' :: 'e' :: rest => Just (JBoolean True, rest)
    'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest => Just (JBoolean False, rest)
    'n' :: 'u' :: 'l' :: 'l' :: rest => Just (JNull, rest)
    other => do
      (d, rest) <- parseNumber other
      pure (JNumber d, rest)

  covering
  parseArray : List JSON -> List Char -> Maybe (JSON, List Char)
  parseArray [] (']' :: rest) = Just (JArray [], rest)
  parseArray acc cs = do
    (v, rest) <- parseValue cs
    case skipWs rest of
      ',' :: more => parseArray (v :: acc) more
      ']' :: more => Just (JArray (reverse (v :: acc)), more)
      _ => Nothing

  covering
  parseObject : List (String, JSON) -> List Char -> Maybe (JSON, List Char)
  parseObject [] ('}' :: rest) = Just (JObject [], rest)
  parseObject acc ('"' :: cs) = do
    (k, rest) <- parseStringBody [] cs
    ':' :: rest' <- Just (skipWs rest)
      | _ => Nothing
    (v, rest'') <- parseValue rest'
    case skipWs rest'' of
      ',' :: more => parseObject ((pack (reverse k), v) :: acc) (skipWs more)
      '}' :: more => Just (JObject (reverse ((pack (reverse k), v) :: acc)), more)
      _ => Nothing
  parseObject _ _ = Nothing

||| Parse a whole text as one value.
export
covering
parse : String -> Maybe JSON
parse s = do
  (v, rest) <- parseValue (unpack s)
  [] <- Just (skipWs rest)
    | _ => Nothing
  pure v

||| Read and parse a whole file.
export covering
readJSONFile : String -> IO (Either String JSON)
readJSONFile path = do
  Right s <- readFile path
    | Left err => pure (Left "\{path}: \{show err}")
  pure (maybe (Left "\{path}: not JSON") Right (parse s))

-------------------------------------------------------------------------------
-- Reading fields

export
field : String -> JSON -> Maybe JSON
field k (JObject kvs) = lookup k kvs
field _ _ = Nothing

export
asString : JSON -> Maybe String
asString (JString s) = Just s
asString _ = Nothing

export
asBool : JSON -> Maybe Bool
asBool (JBoolean b) = Just b
asBool _ = Nothing

export
asInteger : JSON -> Maybe Integer
asInteger (JNumber x) = Just (cast x)
asInteger _ = Nothing

export
asList : JSON -> Maybe (List JSON)
asList (JArray xs) = Just xs
asList _ = Nothing

||| `null` and a missing field are both `Nothing`; anything else must parse.
export
optional : (JSON -> Maybe a) -> Maybe JSON -> Maybe (Maybe a)
optional _ Nothing = Just Nothing
optional _ (Just JNull) = Just Nothing
optional f (Just j) = Just <$> f j

export
nullable : (a -> JSON) -> Maybe a -> JSON
nullable f = maybe JNull f
