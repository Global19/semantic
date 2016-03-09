module Row where

import Data.Functor.Both as Both
import Line
import Prelude hiding (fst, snd)

-- | A row in a split diff, composed of a before line and an after line.
newtype Row a = Row { unRow :: Both (Line a) }
  deriving (Eq, Foldable, Functor, Show, Traversable)

makeRow :: Line a -> Line a -> Row a
makeRow a = Row . both a

-- | Merge open lines and prepend closed lines (as determined by a pair of functions) onto a list of rows.
adjoinRowsBy :: Both (a -> Bool) -> Row a -> [Row a] -> [Row a]
adjoinRowsBy _ row [] = [ row ]
adjoinRowsBy f row (nextRow : rows) = zipWithDefaults makeRow mempty (coalesceLinesBy <$> f <*> unRow row <*> unRow nextRow) ++ rows
