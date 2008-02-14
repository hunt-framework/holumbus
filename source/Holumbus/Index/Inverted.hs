-- ----------------------------------------------------------------------------

{- |
  Module     : Holumbus.Index.Inverted
  Copyright  : Copyright (C) 2007, 2008 Sebastian M. Schlatt, Timo B. Huebel
  License    : MIT
  
  Maintainer : Timo B. Huebel (tbh@holumbus.org)
  Stability  : experimental
  Portability: portable
  Version    : 0.3
  
  The inverted index for Holumbus. For extensive documentation of the index
  interface, see class 'HolIndex' in "Holumbus.Index.Common".

-}

-- ----------------------------------------------------------------------------

module Holumbus.Index.Inverted 
(
  -- * Inverted index types
  InvIndex (..)
  , Parts
  , Part
  
  -- * Construction
  , singleton
  , emptyInverted
)
where

import Text.XML.HXT.Arrow

import Data.Function
import Data.Maybe
import Data.Binary
import Data.List

import Data.Map (Map)
import qualified Data.Map as M

import qualified Data.IntMap as IM
import qualified Data.IntSet as IS

import Holumbus.Data.StrMap (StrMap)
import qualified Holumbus.Data.StrMap as SM

import Holumbus.Index.Common
import Holumbus.Index.Compression

import Control.Parallel.Strategies

-- | The index consists of a table which maps documents to ids and a number of index parts.
newtype InvIndex = InvIndex 
  { indexParts :: Parts  -- ^ The parts of the index, each representing one context.
  } deriving (Show, Eq)

-- | The index parts are identified by a name, which should denote the context of the words.
type Parts       = Map Context Part
-- | The index part is the real inverted index. Words are mapped to their occurrences.
type Part        = StrMap CompressedOccurrences

instance HolIndex InvIndex where
  sizeWords = M.fold ((+) . SM.size) 0 . indexParts
  contexts = map fst . M.toList . indexParts

  allWords i c = map (\(w, o) -> (w, inflateOcc o)) $ SM.toList $ getPart c i
  prefixCase i c q = map (\(w, o) -> (w, inflateOcc o)) $ SM.prefixFindWithKey q $ getPart c i
  prefixNoCase i c q = map (\(w, o) -> (w, inflateOcc o)) $ SM.prefixFindNoCaseWithKey q $ getPart c i
  lookupCase i c q = map (\o -> (q, inflateOcc o)) $ maybeToList (SM.lookup q $ getPart c i)
  lookupNoCase i c q = map (\(w, o) -> (w, inflateOcc o)) $ SM.lookupNoCase q $ getPart c i

  mergeIndexes i1 i2 = InvIndex (mergeParts (indexParts i1) (indexParts i2))
  substractIndexes i1 i2 = InvIndex (substractParts (indexParts i1) (indexParts i2))

  insertOccurrences c w o i = mergeIndexes (singleton c w o) i
  deleteOccurrences c w o i = substractIndexes i (singleton c w o)

  splitByContexts (InvIndex parts) = splitInternal (map annotate $ M.toList parts)
    where
    annotate (c, p) = let i = InvIndex (M.singleton c p) in (sizeWords i, i)

  splitByDocuments i = splitInternal (map convert $ IM.toList $ IM.unionsWith unionDocs docResults)
    where
    unionDocs = M.unionWith (M.unionWith IS.union)
    docResults = map (\c -> resultByDocument c (allWords i c)) (contexts i)
    convert (d, cs) = foldl' makeIndex (0, emptyInverted) (M.toList cs)
      where
      makeIndex r (c, ws) = foldl' makeOcc r (M.toList ws)
        where
        makeOcc (rs, ri) (w, p) = (IS.size p + rs , insertOccurrences c w (IM.singleton d p) ri)

  splitByWords i = splitInternal indexes
    where
    indexes = map convert $ M.toList $ M.unionsWith (M.unionWith mergeOccurrences) wordResults
      where
      wordResults = map (\c -> resultByWord c (allWords i c)) (contexts i)
      convert (w, cs) = foldl' makeIndex (0, emptyInverted) (M.toList cs)
        where
        makeIndex (rs, ri) (c, o) = (rs + sizeOccurrences o, insertOccurrences c w o ri)

  updateDocuments f (InvIndex parts) = InvIndex (M.mapWithKey updatePart parts)
    where
    updatePart c p = SM.mapWithKey (\w o -> IM.foldWithKey (updateDocument c w) IM.empty o) p
    updateDocument c w d p r = IM.insertWith mergePositions (f c w d) p r
      where
      mergePositions p1 p2 = deflatePos $ IS.union (inflatePos p1) (inflatePos p2)

instance NFData InvIndex where
  rnf (InvIndex parts) = rnf parts

instance XmlPickler InvIndex where
  xpickle =  xpElem "indexes" $ xpWrap (\p -> InvIndex p, \(InvIndex p) -> p) xpParts

instance Binary InvIndex where
  put (InvIndex parts) = put parts
  get = do parts <- get
           return (InvIndex parts)

-- | Create an index with just one word in one context.
singleton :: Context -> String -> Occurrences -> InvIndex
singleton c w o = InvIndex (M.singleton c (SM.singleton w (deflateOcc o)))

-- | Merge two sets of index parts.
mergeParts :: Parts -> Parts -> Parts
mergeParts = M.unionWith mergePart

-- | Merge two index parts.
mergePart :: Part -> Part -> Part
mergePart = SM.unionWith mergeDiffLists
  where
  mergeDiffLists o1 o2 = deflateOcc $ mergeOccurrences (inflateOcc o1) (inflateOcc o2)

-- | Substract a set of index parts from another.
substractParts :: Parts -> Parts -> Parts
substractParts = M.differenceWith substractPart

-- | Substract one index part from another.
substractPart :: Part -> Part -> Maybe Part
substractPart p1 p2 = if SM.null diffPart then Nothing else Just diffPart
  where
  diffPart = SM.differenceWith substractDiffLists p1 p2
    where
    substractDiffLists o1 o2 = if diffOcc == emptyOccurrences then Nothing else Just (deflateOcc diffOcc)
      where
      diffOcc = substractOccurrences (inflateOcc o1) (inflateOcc o2)

-- | Internal split function used by the split functions from the HolIndex interface (above).
splitInternal :: [(Int, InvIndex)] -> Int -> [InvIndex]
splitInternal inp n = allocate mergeIndexes stack buckets
  where
  buckets = zipWith const (createBuckets n) stack
  stack = reverse (sortBy (compare `on` fst) inp)

-- | Allocates values from the first list to the buckets in the second list.
allocate :: (a -> a -> a) -> [(Int, a)] -> [(Int, a)] -> [a]
allocate _ _ [] = []
allocate _ [] ys = map snd ys
allocate f (x:xs) (y:ys) = allocate f xs (sortBy (compare `on` fst) ((combine x y):ys))
  where
  combine (s1, v1) (s2, v2) = (s1 + s2, f v1 v2)

-- | Create empty buckets for allocating indexes.  
createBuckets :: Int -> [(Int, InvIndex)]
createBuckets n = (replicate n (0, emptyInverted))
  
-- | Create an empty index.
emptyInverted :: InvIndex
emptyInverted = InvIndex M.empty
                  
-- | Return a part of the index for a given context.
getPart :: Context -> InvIndex -> Part
getPart c i = fromMaybe SM.empty (M.lookup c $ indexParts i)

-- | The XML pickler for the index parts.
xpParts :: PU Parts
xpParts = xpWrap (M.fromList, M.toList) (xpList xpContext)
  where
  xpContext = xpElem "part" (xpPair (xpAttr "id" xpText) xpPart)

-- | The XML pickler for a single part.
xpPart :: PU Part
xpPart = xpElem "index" (xpWrap (SM.fromList, SM.toList) (xpList xpWord))
  where
  xpWord = xpElem "word" (xpPair (xpAttr "w" xpText) (xpWrap (deflateOcc, inflateOcc) xpOccurrences))
