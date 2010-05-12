{-# OPTIONS #-}

-- ------------------------------------------------------------

module Holumbus.Crawler.Types
where

import           Control.DeepSeq

import		 Control.Monad.State

import           Data.Binary			( Binary )
import qualified Data.Binary			as B			-- else naming conflict with put and get from Monad.State

import           Data.Function.Selector

import           Holumbus.Crawler.Constants
import           Holumbus.Crawler.URIs
import           Holumbus.Crawler.RobotTypes
import           Holumbus.Crawler.XmlArrows	( checkDocumentStatus )

import		 Text.XML.HXT.Arrow
import           System.Log.Logger		( Priority(..) )

-- ------------------------------------------------------------

-- | The action to combine the result of a single document with the accumulator for the overall crawler result.
-- This combining function runs in the IO monad to enable storing parts of the result externally

type AccumulateDocResult a r	= (URI, a) -> r -> IO r

-- | The folding operator for merging partial results when working with mapFold and parallel crawling

type MergeDocResults       r    =        r -> r -> IO r

-- | The extractor function for a single document

type ProcessDocument	 a	= IOSArrow XmlTree a

-- | The crawler configuration record

data CrawlerConfig a r		= CrawlerConfig
                                  { cc_readAttributes	:: ! Attributes
				  , cc_preRefsFilter	:: IOSArrow XmlTree XmlTree
				  , cc_processRefs	:: IOSArrow XmlTree URI
				  , cc_preDocFilter     :: IOSArrow XmlTree XmlTree
				  , cc_processDoc	:: ProcessDocument a
				  , cc_accumulate	:: AccumulateDocResult a r		-- result accumulation runs in the IO monad to allow storing parts externally
                                  , cc_fold		:: MergeDocResults r
				  , cc_followRef	:: URI -> Bool
				  , cc_addRobotsTxt	:: CrawlerConfig a r -> AddRobotsAction
				  , cc_maxNoOfDocs	:: ! Int
                                  , cc_maxParDocs       :: ! Int
				  , cc_maxParThreads	:: ! Int
				  , cc_saveIntervall	:: ! Int
				  , cc_savePathPrefix	:: ! String
				  , cc_traceLevel	:: ! Priority
                                  , cc_traceLevelHxt	:: ! Priority
				  }

-- | The crawler state record

data CrawlerState r		= CrawlerState
                                  { cs_toBeProcessed    :: ! URIs
				  , cs_alreadyProcessed :: ! URIs
				  , cs_robots		:: ! Robots				-- is part of the state, it will grow during crawling
				  , cs_noOfDocs		:: ! Int				-- stop crawling when this counter reaches 0, (-1) means unlimited # of docs
                                  , cs_noOfDocsSaved    :: ! Int
				  , cs_resultAccu       :: ! r					-- evaluate accumulated result, else memory leaks show up
                                  , cs_resultInit	:: ! r					-- the initial value for folding results
				  }
				  deriving (Show)

instance (NFData r) => NFData (CrawlerState r) where
  rnf CrawlerState { cs_toBeProcessed    = a
                   , cs_alreadyProcessed = b
                   , cs_robots           = c
                   , cs_noOfDocs         = d
                   , cs_noOfDocsSaved    = e
                   , cs_resultAccu       = f
                   , cs_resultInit	 = g
                   }		= rnf a `seq` rnf b `seq` rnf c `seq` rnf d `seq` rnf e `seq` rnf f `seq` rnf g

instance (XmlPickler r) => XmlPickler (CrawlerState r) where
  xpickle		= xpElem "crawler-state" $
                          xpWrap ( \ ((d, e), (a, b, c, f, g)) -> CrawlerState a b c d e f g
                                 , \ (CrawlerState a b c d e f g) -> ( (d, e)
                                                                     , (a, b, c, f, g)
                                                                     )
                                 ) $
                          xpPair ( xpPair
                                   ( xpAttr "no-of-docs"       xpPrim )
                                   ( xpAttr "no-of-docs-saved" xpPrim )
                                 )
                                 ( xp5Tuple
                                   ( xpElem "to-be-processed" $
                                     xpURIs
                                   )
                                   ( xpElem "already-processed" $
                                     xpURIs
                                   )
                                   xpRobots
                                   xpickle
                                   xpickle
                                 )
      where
      xpURIs		= xpWrap ( fromListURIs, toListURIs ) $
                          xpList $
                          xpElem "doc" $
                          xpAttr "href" $
                          xpText

-- ------------------------------------------------------------

-- | selector functions for CrawlerState

theToBeProcessed	:: Selector (CrawlerState r) URIs
theToBeProcessed	= S cs_toBeProcessed	(\ x s -> s {cs_toBeProcessed = x})

theAlreadyProcessed	:: Selector (CrawlerState r) URIs
theAlreadyProcessed	= S cs_alreadyProcessed	(\ x s -> s {cs_alreadyProcessed = x})

theRobots		:: Selector (CrawlerState r) Robots
theRobots		= S cs_robots		(\ x s -> s {cs_robots = x})

theNoOfDocs		:: Selector (CrawlerState r) Int
theNoOfDocs		= S cs_noOfDocs		(\ x s -> s {cs_noOfDocs = x})

theNoOfDocsSaved	:: Selector (CrawlerState r) Int
theNoOfDocsSaved	= S cs_noOfDocsSaved	(\ x s -> s {cs_noOfDocsSaved = x})

theResultAccu		:: Selector (CrawlerState r) r
theResultAccu		= S cs_resultAccu	(\ x s -> s {cs_resultAccu = x})

theResultInit		:: Selector (CrawlerState r) r
theResultInit		= S cs_resultInit	(\ x s -> s {cs_resultInit = x})

-- | selector functions for CrawlerConfig

theReadAttributes	:: Selector (CrawlerConfig a r) Attributes
theReadAttributes	= S cc_readAttributes	(\ x s -> s {cc_readAttributes = x})

theTraceLevel		:: Selector (CrawlerConfig a r) Priority
theTraceLevel		= S cc_traceLevel	(\ x s -> s {cc_traceLevel = x})

theTraceLevelHxt	:: Selector (CrawlerConfig a r) Priority
theTraceLevelHxt	= S cc_traceLevelHxt	(\ x s -> s {cc_traceLevelHxt = x})

theMaxNoOfDocs		:: Selector (CrawlerConfig a r) Int
theMaxNoOfDocs		= S cc_maxNoOfDocs	(\ x s -> s {cc_maxNoOfDocs = x})

theMaxParDocs		:: Selector (CrawlerConfig a r) Int
theMaxParDocs		= S cc_maxParDocs	(\ x s -> s {cc_maxParDocs = x})

theMaxParThreads	:: Selector (CrawlerConfig a r) Int
theMaxParThreads	= S cc_maxParThreads	(\ x s -> s {cc_maxParThreads = x})

theSaveIntervall	:: Selector (CrawlerConfig a r) Int
theSaveIntervall	= S cc_saveIntervall	(\ x s -> s {cc_saveIntervall = x})

theSavePathPrefix	:: Selector (CrawlerConfig a r) String
theSavePathPrefix	= S cc_savePathPrefix	(\ x s -> s {cc_savePathPrefix = x})

theFollowRef		:: Selector (CrawlerConfig a r) (URI -> Bool)
theFollowRef		= S cc_followRef	(\ x s -> s {cc_followRef = x})

theAddRobotsAction	:: Selector (CrawlerConfig a r) (CrawlerConfig a r -> AddRobotsAction)
theAddRobotsAction	= S cc_addRobotsTxt	(\ x s -> s {cc_addRobotsTxt = x})

theAccumulateOp		:: Selector (CrawlerConfig a r) (AccumulateDocResult a r)
theAccumulateOp		= S cc_accumulate	(\ x s -> s {cc_accumulate = x})

theFoldOp		:: Selector (CrawlerConfig a r) (MergeDocResults r)
theFoldOp		= S cc_fold		(\ x s -> s {cc_fold = x})

thePreRefsFilter	:: Selector (CrawlerConfig a r) (IOSArrow XmlTree XmlTree)
thePreRefsFilter	= S cc_preRefsFilter	(\ x s -> s {cc_preRefsFilter = x})

theProcessRefs		:: Selector (CrawlerConfig a r) (IOSArrow XmlTree URI)
theProcessRefs		= S cc_processRefs	(\ x s -> s {cc_processRefs = x})

thePreDocFilter		:: Selector (CrawlerConfig a r) (IOSArrow XmlTree XmlTree)
thePreDocFilter		= S cc_preDocFilter	(\ x s -> s {cc_preDocFilter = x})

theProcessDoc		:: Selector (CrawlerConfig a r) (IOSArrow XmlTree a)
theProcessDoc		= S cc_processDoc	(\ x s -> s {cc_processDoc = x})

-- ------------------------------------------------------------

-- a rather boring default crawler configuration

defaultCrawlerConfig	:: AccumulateDocResult a r -> MergeDocResults r -> CrawlerConfig a r
defaultCrawlerConfig op	op2
			= CrawlerConfig
			  { cc_readAttributes	= [ (curl_user_agent,		defaultCrawlerName)
						  , (curl_max_time,		show $ (60 * 1000::Int))	-- whole transaction for reading a document must complete within 60,000 milli seconds, 
						  , (curl_connect_timeout,	show $ (10::Int))	 	-- connection must be established within 10 seconds
						  ]
			  , cc_preRefsFilter	= this						-- no preprocessing for refs extraction
			  , cc_processRefs	= none						-- don't extract refs
			  , cc_preDocFilter     = checkDocumentStatus				-- default: in case of errors throw away any contents
			  , cc_processDoc	= none						-- no document processing at all
			  , cc_accumulate	= op						-- combining function for result accumulating
                          , cc_fold             = op2
			  , cc_followRef	= const False					-- do not follow any refs
			  , cc_addRobotsTxt	= const $ const return				-- do not add robots.txt evaluation
			  , cc_saveIntervall	= (-1)						-- never save an itermediate state
			  , cc_savePathPrefix	= "/tmp/hc-"					-- the prefix for filenames into which intermediate states are saved
			  , cc_maxNoOfDocs	= (-1)						-- maximum # of docs to be crawled, -1 means unlimited
                          , cc_maxParDocs	= 20						-- maximum # of doc crawled in parallel
			  , cc_maxParThreads    = 5						-- maximum # of threads running in parallel
			  , cc_traceLevel	= NOTICE					-- traceLevel
			  , cc_traceLevelHxt	= WARNING					-- traceLevel for hxt
			  }

theCrawlerName		:: Selector (CrawlerConfig a r) String
theCrawlerName		= theReadAttributes
			  >>>
			  S { getS = lookupDef defaultCrawlerName curl_user_agent
			    , setS = addEntry curl_user_agent
			    }

theMaxTime		:: Selector (CrawlerConfig a r) Int
theMaxTime		= theReadAttributes
			  >>>
			  S { getS = read . lookupDef "0" curl_max_time
			    , setS = addEntry curl_max_time . show . (`max` 1)
			    }

theConnectTimeout	:: Selector (CrawlerConfig a r) Int
theConnectTimeout	= theReadAttributes
			  >>>
			  S { getS = read . lookupDef "0" curl_connect_timeout
			    , setS = addEntry curl_connect_timeout . show . (`max` 1)
			    }


-- ------------------------------------------------------------

-- | Add attributes for accessing documents

addReadAttributes	:: Attributes -> CrawlerConfig a r -> CrawlerConfig a r
addReadAttributes al	= update theReadAttributes (addEntries al)

-- | Insert a robots no follow filter before thePreRefsFilter

addRobotsNoFollow	:: CrawlerConfig a r -> CrawlerConfig a r
addRobotsNoFollow	= update thePreRefsFilter ( robotsNoFollow >>> )

-- | Insert a robots no follow filter before thePreRefsFilter

addRobotsNoIndex	:: CrawlerConfig a r -> CrawlerConfig a r
addRobotsNoIndex	= update thePreDocFilter ( robotsNoIndex >>> )


-- | Set the log level

setCrawlerTraceLevel	:: Priority -> Priority -> CrawlerConfig a r -> CrawlerConfig a r
setCrawlerTraceLevel l lx
			= setS theTraceLevel l
                          >>>
                          setS theTraceLevelHxt lx

-- | Set save intervall in config

setCrawlerSaveConf	:: Int -> String -> CrawlerConfig a r -> CrawlerConfig a r
setCrawlerSaveConf i f	= setS theSaveIntervall i
                          >>>
                          setS theSavePathPrefix f

-- | Set max # of documents to be crawled
-- and max # of documents crawled in parallel

setCrawlerMaxDocs	:: Int -> Int -> Int -> CrawlerConfig a r -> CrawlerConfig a r
setCrawlerMaxDocs mxd mxp mxt
			= setS theMaxNoOfDocs mxd
                          >>>
                          setS theMaxParDocs mxp
			  >>>
			  setS theMaxParThreads mxt

-- | Set the pre hook filter executed before the hrefs are collected

setCrawlerPreRefsFilter	:: IOSArrow XmlTree XmlTree -> CrawlerConfig a r -> CrawlerConfig a r
setCrawlerPreRefsFilter f
			= setS thePreRefsFilter f

-- ------------------------------------------------------------

instance (Binary r) => Binary (CrawlerState r) where
    put	s		= do
			  B.put (getS theToBeProcessed s)
			  B.put (getS theAlreadyProcessed s)
			  B.put (getS theRobots s)
			  B.put (getS theNoOfDocs s)
			  B.put (getS theNoOfDocsSaved s)
			  B.put (getS theResultAccu s)
			  B.put (getS theResultInit s)
    get			= do
			  tbp <- B.get
			  alp <- B.get
			  rbt <- B.get
			  mxd <- B.get
                          mxs <- B.get
			  acc <- B.get
                          ini <- B.get
			  return $ CrawlerState
				   { cs_toBeProcessed    = tbp
				   , cs_alreadyProcessed = alp
				   , cs_robots           = rbt
				   , cs_noOfDocs         = mxd
                                   , cs_noOfDocsSaved    = mxs
				   , cs_resultAccu       = acc
				   , cs_resultInit       = ini
				   }

putCrawlerState		:: (Binary r) => CrawlerState	r -> B.Put
putCrawlerState		= B.put

getCrawlerState		:: (Binary r) => B.Get (CrawlerState r)
getCrawlerState		= B.get

initCrawlerState	:: r -> CrawlerState r
initCrawlerState r	= CrawlerState
			  { cs_toBeProcessed    = emptyURIs
			  , cs_alreadyProcessed = emptyURIs
			  , cs_robots		= emptyRobots
			  , cs_noOfDocs		= 0
                          , cs_noOfDocsSaved    = 0
			  , cs_resultAccu	= r
			  , cs_resultInit	= r
			  }

-- ------------------------------------------------------------

