{-# LANGUAGE AllowAmbiguousTypes, DataKinds, DisambiguateRecordFields, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, NamedFieldPuns, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Language.Python.Tags
( Term(..)
) where

import           Control.Effect.Reader
import           Control.Effect.Writer
import           Data.Foldable (traverse_)
import           Data.Maybe (listToMaybe)
import           Data.Monoid (Ap(..))
import           Data.List.NonEmpty (NonEmpty(..))
import           Data.Text as Text
import           GHC.Generics
import           Source.Loc
import           Source.Range
import           Source.Source as Source
import           Tags.Tag
import qualified Tags.Taggable.Precise as Tags
import qualified TreeSitter.Python.AST as Py

newtype Term a = Term { getTerm :: Py.Module a }

instance Tags.ToTags Term where
  tags src = Tags.runTagging src . tags . getTerm


class ToTags t where
  tags
    :: ( Carrier sig m
       , Member (Reader Source) sig
       , Member (Writer Tags.Tags) sig
       )
    => t Loc
    -> m ()

instance (ToTagsBy strategy t, strategy ~ ToTagsInstance t) => ToTags t where
  tags = tags' @strategy


class ToTagsBy (strategy :: Strategy) t where
  tags'
    :: ( Carrier sig m
       , Member (Reader Source) sig
       , Member (Writer Tags.Tags) sig
       )
    => t Loc
    -> m ()


data Strategy = Generic | Custom

type family ToTagsInstance t :: Strategy where
  ToTagsInstance (_ :+: _)             = 'Custom
  ToTagsInstance Py.FunctionDefinition = 'Custom
  ToTagsInstance Py.ClassDefinition    = 'Custom
  ToTagsInstance Py.Call               = 'Custom
  ToTagsInstance _                     = 'Generic


instance (ToTags l, ToTags r) => ToTagsBy 'Custom (l :+: r) where
  tags' (L1 l) = tags l
  tags' (R1 r) = tags r

instance ToTagsBy 'Custom Py.FunctionDefinition where
  tags' Py.FunctionDefinition
    { ann = Loc Range { start } span
    , name = Py.Identifier { bytes = name }
    , parameters
    , returnType
    , body = Py.Block { ann = Loc Range { start = end } _, extraChildren }
    } = do
      src <- ask @Source
      let docs = listToMaybe extraChildren >>= docComment src
          sliced = slice src (Range start end)
      Tags.yield (Tag name Function span (firstLine sliced) docs)
      tags parameters
      traverse_ tags returnType
      traverse_ tags extraChildren

instance ToTagsBy 'Custom Py.ClassDefinition where
  tags' Py.ClassDefinition
    { ann = Loc Range { start } span
    , name = Py.Identifier { bytes = name }
    , superclasses
    , body = Py.Block { ann = Loc Range { start = end } _, extraChildren }
    } = do
      src <- ask @Source
      let docs = listToMaybe extraChildren >>= docComment src
          sliced = slice src (Range start end)
      Tags.yield (Tag name Class span (firstLine sliced) docs)
      traverse_ tags superclasses
      traverse_ tags extraChildren

instance ToTagsBy 'Custom Py.Call where
  tags' Py.Call
    { ann = Loc range span
    , function = Py.IdentifierPrimaryExpression Py.Identifier { bytes = name }
    , arguments
    } = do
      src <- ask @Source
      let sliced = slice src range
      Tags.yield (Tag name Call span (firstLine sliced) Nothing)
      tags arguments
  tags' Py.Call { function, arguments } = tags function >> tags arguments

docComment :: Source -> (Py.CompoundStatement :+: Py.SimpleStatement) Loc -> Maybe Text
docComment src (R1 (Py.ExpressionStatementSimpleStatement (Py.ExpressionStatement { extraChildren = L1 (Py.PrimaryExpressionExpression (Py.StringPrimaryExpression Py.String { ann })) :|_ }))) = Just (toText (slice src (byteRange ann)))
docComment _ _ = Nothing

firstLine :: Source -> Text
firstLine = Text.takeWhile (/= '\n') . toText . Source.take 180


instance (Generic1 t, Tags.GFoldable1 ToTags (Rep1 t)) => ToTagsBy 'Generic t where
  tags' = getAp . Tags.gfoldMap1 @ToTags (Ap . tags) . from1
