-- ----------------------------------------------------------------------------

{- |
  Module     : Holumbus.Index.Common
  Copyright  : Copyright (C) 2007 Sebastian M. Schlatt, Timo B. Huebel
  License    : MIT

  Maintainer : Timo B. Huebel (t.h@gmx.info)
  Stability  : experimental
  Portability: portable
  Version    : 0.2

  Common data types shared by all index types and a unified interface for
  all different index types.

-}

-- ----------------------------------------------------------------------------

module Holumbus.Index.Common 
  (
  -- * Common index types and classes
  Position
  , Context
  , Document
  , DocId
  , URI
  , Title
  , Content
  , Word
  , Occurrences
  , Positions
  , HolIndex (..)
  , HolDocuments (..)

  -- * Indexes and Documents
  , mergeAll

  -- * Occurrences
  , emptyOccurrences
  , sizeOccurrences
  , mergeOccurrences

  -- * Pickling
  , xpDocument
  , xpOccurrences
  , xpPositions
  
  -- * Persistent storage
  , loadFromFile

  , loadFromXmlFile
  , loadFromBinFile
  , writeToXmlFile
  , writeToBinFile
  )
where

import Text.XML.HXT.Arrow

import Data.Maybe

import qualified Data.List as L

import Data.Binary (Binary)
import qualified Data.Binary as B

import Data.IntMap (IntMap)
import qualified Data.IntMap as IM

import Data.IntSet (IntSet)
import qualified Data.IntSet as IS

-- | A document consists of a title and its unique identifier.
type Document      = (Title, URI)

-- | The unique identifier of a document (created upon insertion into the document table).
type DocId         = Int
-- | The URI describing the location of the original document.
type URI           = String
-- | The title of a document.
type Title         = String
-- | The content of a document.
type Content       = String

-- | The position of a word in the document.
type Position      = Int
-- | The name of a context.
type Context       = String
-- | A single word.
type Word          = String

-- | The occurrences in a number of documents. A mapping from document ids to the positions in the document.
type Occurrences   = IntMap Positions
-- | The positions of the word in the document.
type Positions     = IntSet

-- | This class provides a generic interface to different types of index implementations.
class HolIndex i where
  -- | Returns the number of unique words in the index.
  sizeWords     :: i -> Int
  -- | Returns a list of all contexts avaliable in the index.
  contexts      :: i -> [Context]

  -- | Returns the occurrences for every word. A potentially expensive operation.
  allWords      :: i -> Context -> [(String, Occurrences)]
  -- | Searches for words beginning with the prefix in a given context (case-sensitive).
  prefixCase    :: i -> Context -> String -> [(String, Occurrences)]
  -- | Searches for words beginning with the prefix in a given context (case-insensitive).
  prefixNoCase  :: i -> Context -> String -> [(String, Occurrences)]
  -- | Searches for and exact word in a given context (case-sensitive).
  lookupCase    :: i -> Context -> String -> [(String, Occurrences)]
  -- | Searches for and exact word in a given context (case-insensitive).
  lookupNoCase  :: i -> Context -> String -> [(String, Occurrences)]
  
  -- | Insert occurrences.
  insertOccurrences :: Context -> String -> Occurrences -> i -> i
  -- | Delete occurrences.
  deleteOccurrences :: Context -> String -> Occurrences -> i -> i

  -- | Merges two indexes. 
  mergeIndexes  :: i -> i -> i
  -- | Substract one index from another.
  substractIndexes :: i -> i -> i

  -- | Splitting an index by its contexts.
  splitByContexts :: i -> Int -> [i]
  -- | Splitting an index by its documents.
  splitByDocuments :: i -> Int -> [i]
  -- | Splitting an index by its words.
  splitByWords :: i -> Int -> [i]

  -- | Update document id's (e.g. for renaming documents). If the function maps two different id's
  -- to the same new id, the two sets of word positions will be merged if both old id's are present
  -- in the occurrences for a word in a specific context.
  updateDocuments :: (Context -> Word -> DocId -> DocId) -> i -> i

class HolDocuments d where
  -- | Returns the number of unique documents in the table.
  sizeDocs      :: d -> Int
  
  -- | Lookup a document by its id.
  lookupById    :: Monad m => d -> DocId -> m Document
  -- | Lookup the id of a document by an URI.
  lookupByURI   :: Monad m => d -> URI -> m DocId
  
  -- | Retrieves the full text of a document.
  getDocText    :: d -> DocId -> Content

  -- | Merge two document tables. The returned tuple contains a list of id's from the second
  -- table that were replaced with new id's to avoid collisions.
  mergeDocs     :: d -> d -> ([(DocId, DocId)] ,d)

-- | Insert a document into the table. Returns a tuple of the id for that document and the 
-- new table. If a document with the same URI is already present, its id will be returned 
-- and the table is returned unchanged.
  insertDoc     :: d -> Document -> (DocId, d)

-- | The XML pickler for a single document.
xpDocument :: PU Document
xpDocument = xpPair xpTitle xpURI
  where
  xpURI           = xpAttr "href" xpText
  xpTitle         = xpAttr "title" xpText

-- | The XML pickler for a set of positions.
xpPositions :: PU Positions
xpPositions = xpWrap ( IS.fromList . (map read) . words
                     , unwords . (map show) . IS.toList
                     ) xpText

-- | The XML pickler for the occurrences of a word.
xpOccurrences :: PU Occurrences
xpOccurrences = xpWrap (IM.fromList, IM.toList) (xpList xpOccurrence)
  where
  xpOccurrence = xpElem "doc" (xpPair (xpAttr "idref" xpPrim) xpPositions)

-- | Merges an index with its documents table with another index and its documents table. 
-- Conflicting id's for documents will be resolved automatically.
mergeAll :: (HolDocuments d, HolIndex i) => d -> i -> d -> i -> (d, i)
mergeAll d1 i1 d2 i2 = (md, mergeIndexes i1 (updateDocuments replaceIds i2))
  where
  (ud, md) = mergeDocs d1 d2
  idTable = IM.fromList ud
  replaceIds _ _ d = fromMaybe d (IM.lookup d idTable)

-- | Create an empty set of positions.
emptyOccurrences :: Occurrences
emptyOccurrences = IM.empty

-- | Determine the number of positions in a set of occurrences.
sizeOccurrences :: Occurrences -> Int
sizeOccurrences = IM.fold ((+) . IS.size) 0

-- | Merge two occurrences.
mergeOccurrences :: Occurrences -> Occurrences -> Occurrences
mergeOccurrences = IM.unionWith (IS.union)

-- | Try to determine the file type automatically. The file is loaded as XML if the filename
-- ends with \".xml\" and otherwise is loaded as binary file.
loadFromFile :: (XmlPickler a, Binary a) => FilePath -> IO a
loadFromFile f = if L.isSuffixOf ".xml" f then loadFromXmlFile f else loadFromBinFile f
 
-- | Load from XML file.
loadFromXmlFile :: XmlPickler a => FilePath -> IO a
loadFromXmlFile f = do
                    r <- runX (xunpickleDocument xpickle options f)
                    return $! head r
                    where
                    options = [ (a_remove_whitespace, v_1), (a_encoding, utf8), (a_validate, v_0) ]     

-- | Write to XML file.
writeToXmlFile :: XmlPickler a => FilePath -> a -> IO ()
writeToXmlFile f i = do
                     runX (constA i >>> xpickleDocument xpickle options f)
                     return ()
                     where
                     options = [ (a_indent, v_1), (a_output_encoding, utf8), (a_validate, v_0) ]     

-- | Load from a binary file.
loadFromBinFile :: Binary a => FilePath -> IO a
loadFromBinFile f = B.decodeFile f

-- | Write to a binary file.
writeToBinFile :: Binary a => FilePath -> a -> IO ()
writeToBinFile =  B.encodeFile 
