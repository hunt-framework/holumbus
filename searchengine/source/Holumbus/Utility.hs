-- ----------------------------------------------------------------------------

{- |
  Module     : Holumbus.Utility
  Copyright  : Copyright (C) 2008 Timo B. Huebel
  License    : MIT

  Maintainer : Timo B. Huebel (tbh@holumbus.org)
  Stability  : experimental
  Portability: portable
  Version    : 0.1

  Small utility functions which are probably useful somewhere else, too.

-}

-- ----------------------------------------------------------------------------

module Holumbus.Utility where

import Data.Char

import System.IO

import           Numeric
import           Holumbus.Index.Common
import qualified Holumbus.Index.Documents as DOC

import           Control.Exception (bracket)

import           Data.Binary
import qualified Data.ByteString.Lazy as B
import           Data.Maybe

import qualified Data.IntMap as IM
import qualified Data.List as L


import           Text.XML.HXT.Arrow

import           Data.Digest.MD5
import           Data.ByteString.Lazy.Char8(pack)


-- | Split a string into seperate strings at a specific character sequence.
split :: Eq a => [a] -> [a] -> [[a]]
split _ []       = [[]] 
split at w@(x:xs) = maybe ((x:r):rs) ((:) [] . split at) (L.stripPrefix at w)
                    where (r:rs) = split at xs
 
-- | Join with a seperating character sequence.
join :: Eq a => [a] -> [[a]] -> [a]
join = L.intercalate

-- | Removes leading and trailing whitespace from a string.
strip :: String -> String
strip = stripWith isSpace

-- | Strip leading and trailing elements matching a predicate.
stripWith :: (a -> Bool) -> [a] -> [a]
stripWith f = reverse . dropWhile f . reverse . dropWhile f

 
-- found on the haskell cafe mailing list
-- http:\/\/www.haskell.org\/pipermail\/haskell-cafe\/2008-April\/041970.html
strictDecodeFile :: Binary a => FilePath -> IO a
strictDecodeFile f  =
    bracket (openBinaryFile f ReadMode) hClose $ \h -> do
                                                       print ("Decoding " ++ f)
                                                       c <- B.hGetContents h
                                                       return $! decode c  

-- | partition the list of input data into a list of input data lists of
--   approximately the same length
partitionList :: Int -> [a] -> [[a]]
partitionList _ [] = []
partitionList count l  = [take count l] ++ (partitionList count (drop count l)) 

-- | Escapes non-alphanumeric or space characters in a String
escape :: String -> String 
escape []     = []
escape (c:cs)
  = if isAlphaNum c || isSpace c 
      then c : escape cs
      else '%' : showHex (fromEnum c) "" ++ escape cs
      
 
-- | Computes a filename for a local temporary file.
--   Since filename computation might depend on the DocId it is also submitted
--   as a parameter
tmpFile :: DocId -> URI -> String
tmpFile _ u = let f = escape u
              in if (length f) > 255
                   then (show . md5 . pack) f
                   else f
-- | Helper function to replace original URIs by the corresponding pathes for 
--   the locally saved files     
tmpDocs :: HolDocuments d a => String -> d a -> d a
tmpDocs tmpPath =  
    fromMap 
  . (IM.mapWithKey (\docId doc -> Document (title doc) (tmpPath ++ (tmpFile docId (uri doc))) Nothing))
  . toMap         
      

-- | Compute the base of a webpage
--   stolen from Uwe Schmidt, http:\/\/www.haskell.org\/haskellwiki\/HXT
computeDocBase  :: ArrowXml a => a XmlTree String
computeDocBase
    = ( ( ( this
      /> hasName "html"
      /> hasName "head"
      /> hasName "base"
      >>> getAttrValue "href"
    )
    &&&
    getAttrValue "transfer-URI"
  )
  >>> expandURI
      )
      `orElse`
      getAttrValue "transfer-URI"  
      
      
traceOffset :: Int
traceOffset = 3
      