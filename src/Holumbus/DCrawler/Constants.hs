{-# OPTIONS #-}

-- ------------------------------------------------------------

module Holumbus.DCrawler.Constants
where

defaultCrawlerName	:: String
defaultCrawlerName	= "HolumBot/0.2 @http://holumbus.fh-wedel.de -" ++ "-location"

curl_user_agent		:: String
curl_user_agent		= "curl-" ++ "-user-agent"

curl_max_time		:: String
curl_max_time           = "curl-" ++ "-max-time"

curl_connect_timeout	:: String
curl_connect_timeout	= "curl-" ++ "-connect-timeout"

curl_max_filesize	:: String
curl_max_filesize	= "curl-" ++ "-max-filesize"

curl_location		:: String
curl_location		= "curl-" ++ "-location"

curl_max_redirects	:: String
curl_max_redirects	= "curl-" ++ "-max-redirs"

curl_ssl_verifypeer  :: String
curl_ssl_verifypeer  = "curl-" ++ "-verify-peer"

http_location		:: String
http_location		= "http-location"

http_last_modified	:: String
http_last_modified	= "http-Last-Modified"
-- ------------------------------------------------------------

