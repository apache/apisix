--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local ipairs = ipairs
local core = require("apisix.core")
local stringx = require('pl.stringx')
local type = type
local str_strip = stringx.strip
local re_find = ngx.re.find

local MATCH_NONE = 0
local MATCH_ALLOW = 1
local MATCH_DENY = 2
local MATCH_BOT = 3

local lrucache_useragent = core.lrucache.new({ ttl = 300, count = 1024 })

local schema = {
    type = "object",
    properties = {
        message = {
            type = "string",
            minLength = 1,
            maxLength = 1024,
            default = "Not allowed"
        },
        whitelist = {
            type = "array",
            minItems = 1
        },
        blacklist = {
            type = "array",
            minItems = 1
        },
    },
    additionalProperties = false,
}

local plugin_name = "bot-restriction"

local _M = {
    version = 0.1,
    priority = 2999,
    name = plugin_name,
    schema = schema,
}

-- List taken from https://github.com/ua-parser/uap-core/blob/master/regexes.yaml
local well_known_bots = {
    [[(Pingdom\.com_bot_version_)(\d+)\.(\d+)]],
    [[(facebookexternalhit)/(\d+)\.(\d+)]],
    [[Google.{0,50}/\+/web/snippet]],
    [[(NewRelicPinger)/(\d+)\.(\d+)],
    [[\b(Boto3?|JetS3t|aws-(?:cli|sdk-(?:cpp|go|java|nodejs|ruby2?|dotnet-(?:\d{1,2}|c]]
            .. [[ore)))|s3fs)/(\d+)\.(\d+)(?:\.(\d+)|)]],
    [[ PTST/\d+(?:\.)?\d+$]],
    [[/((?:Ant-)?Nutch|[A-z]+[Bb]ot|[A-z]+[Ss]pider|Axtaris|fetchurl|Isara|ShopSalad|T]]
            .. [[ailsweep)[ \-](\d+)(?:\.(\d+)(?:\.(\d+))?)?]],
    [[\b(008|Altresium|Argus|BaiduMobaider|BoardReader|DNSGroup|DataparkSearch|EDI|Goo]]
            .. [[dzer|Grub|INGRID|Infohelfer|LinkedInBot|LOOQ|Nutch|OgScrper|PathDefender|Peew|Po]]
            .. [[stPost|Steeler|Twitterbot|VSE|WebCrunch|WebZIP|Y!J-BR[A-Z]|YahooSeeker|envolk|sp]]
            .. [[roose|wminer)/(\d+)(?:\.(\d+)|)(?:\.(\d+)|)]],
    [[(MSIE) (\d+)\.(\d+)([a-z]\d|[a-z]|);.{0,200} MSIECrawler]],
    [[(Google-HTTP-Java-Client|Apache-HttpClient|Go-http-client|scalaj-http|http%20cli]]
            .. [[ent|Python-urllib|HttpMonitor|TLSProber|WinHTTP|JNLP|okhttp|aihttp|reqwest|axios]]
            .. [[|unirest-(?:java|python|ruby|nodejs|php|net))(?:[ /](\d+)(?:\.(\d+)|)(?:\.(\d+)|]]
            .. [[)|)]],
    [[(CSimpleSpider|Cityreview Robot|CrawlDaddy|CrawlFire|Finderbots|Index crawler|Jo]]
            .. [[b Roboter|KiwiStatus Spider|Lijit Crawler|QuerySeekerSpider|ScollSpider|Trends C]]
            .. [[rawler|USyd-NLP-Spider|SiteCat Webbot|BotName\/\$BotVersion|123metaspider-Bot|14]]
            .. [[70\.net crawler|50\.nu|8bo Crawler Bot|Aboundex|Accoona-[A-z]{1,30}-Agent|AdsBot]]
            .. [[-Google(?:-[a-z]{1,30}|)|altavista|AppEngine-Google|archive.{0,30}\.org_bot|arch]]
            .. [[iver|Ask Jeeves|[Bb]ai[Dd]u[Ss]pider(?:-[A-Za-z]{1,30})(?:-[A-Za-z]{1,30}|)|bing]]
            .. [[bot|BingPreview|blitzbot|BlogBridge|Bloglovin|BoardReader Blog Indexer|BoardRead]]
            .. [[er Favicon Fetcher|boitho.com-dc|BotSeer|BUbiNG|\b\w{0,30}favicon\w{0,30}\b|\bYe]]
            .. [[ti(?:-[a-z]{1,30}|)|Catchpoint(?: bot|)|[Cc]harlotte|Checklinks|clumboot|Comodo ]]
            .. [[HTTP\(S\) Crawler|Comodo-Webinspector-Crawler|ConveraCrawler|CRAWL-E|CrawlConver]]
            .. [[a|Daumoa(?:-feedfetcher|)|Feed Seeker Bot|Feedbin|findlinks|Flamingo_SearchEngin]]
            .. [[e|FollowSite Bot|furlbot|Genieo|gigabot|GomezAgent|gonzo1|(?:[a-zA-Z]{1,30}-|)Go]]
            .. [[oglebot(?:-[a-zA-Z]{1,30}|)|Google SketchUp|grub-client|gsa-crawler|heritrix|Hid]]
            .. [[denMarket|holmes|HooWWWer|htdig|ia_archiver|ICC-Crawler|Icarus6j|ichiro(?:/mobil]]
            .. [[e|)|IconSurf|IlTrovatore(?:-Setaccio|)|InfuzApp|Innovazion Crawler|InternetArchi]]
            .. [[ve|IP2[a-z]{1,30}Bot|jbot\b|KaloogaBot|Kraken|Kurzor|larbin|LEIA|LesnikBot|Lingu]]
            .. [[ee Bot|LinkAider|LinkedInBot|Lite Bot|Llaut|lycos|Mail\.RU_Bot|masscan|masidani_]]
            .. [[bot|Mediapartners-Google|Microsoft .{0,30} Bot|mogimogi|mozDex|MJ12bot|msnbot(?:]]
            .. [[-media {0,2}|)|msrbot|Mtps Feed Aggregation System|netresearch|Netvibes|NewsGato]]
            .. [[r[^/]{0,30}|^NING|Nutch[^/]{0,30}|Nymesis|ObjectsSearch|OgScrper|Orbiter|OOZBOT|]]
            .. [[PagePeeker|PagesInventory|PaxleFramework|Peeplo Screenshot Bot|PlantyNet_WebRobo]]
            .. [[t|Pompos|Qwantify|Read%20Later|Reaper|RedCarpet|Retreiver|Riddler|Rival IQ|scoot]]
            .. [[er|Scrapy|Scrubby|searchsight|seekbot|semanticdiscovery|SemrushBot|Simpy|SimpleP]]
            .. [[ie|SEOstats|SimpleRSS|SiteCon|Slackbot-LinkExpanding|Slack-ImgProxy|Slurp|snappy]]
            .. [[|Speedy Spider|Squrl Java|Stringer|TheUsefulbot|ThumbShotsBot|Thumbshots\.ru|Tin]]
            .. [[y Tiny RSS|Twitterbot|WhatsApp|URL2PNG|Vagabondo|VoilaBot|^vortex|Votay bot|^voy]]
            .. [[ager|WASALive.Bot|Web-sniffer|WebThumb|WeSEE:[A-z]{1,30}|WhatWeb|WIRE|WordPress|]]
            .. [[Wotbox|www\.almaden\.ibm\.com|Xenu(?:.s|) Link Sleuth|Xerka [A-z]{1,30}Bot|yacy(]]
            .. [[?:bot|)|YahooSeeker|Yahoo! Slurp|Yandex\w{1,30}|YodaoBot(?:-[A-z]{1,30}|)|Yottaa]]
            .. [[Monitor|Yowedo|^Zao|^Zao-Crawler|ZeBot_www\.ze\.bz|ZooShot|ZyBorg)(?:[ /]v?(\d+)]]
            .. [[(?:\.(\d+)(?:\.(\d+)|)|)|)]],
    [[(?:\/[A-Za-z0-9\.]+|) {0,5}([A-Za-z0-9 \-_\!\[\]:]{0,50}(?:[Aa]rchiver|[Ii]ndexe]]
            .. [[r|[Ss]craper|[Bb]ot|[Ss]pider|[Cc]rawl[a-z]{0,50}))[/ ](\d+)(?:\.(\d+)(?:\.(\d+)]]
            .. [[|)|)]],
    [[(?:\/[A-Za-z0-9\.]+|) {0,5}([A-Za-z0-9 \-_\!\[\]:]{0,50}(?:[Aa]rchiver|[Ii]ndexe]]
            .. [[r|[Ss]craper|[Bb]ot|[Ss]pider|[Cc]rawl[a-z]{0,50})) (\d+)(?:\.(\d+)(?:\.(\d+)|)|]]
            .. [[)]],
    [[((?:[A-z0-9]{1,50}|[A-z\-]{1,50} ?|)(?: the |)(?:[Ss][Pp][Ii][Dd][Ee][Rr]|[Ss]cr]]
            .. [[ape|[Cc][Rr][Aa][Ww][Ll])[A-z0-9]{0,50})(?:(?:[ /]| v)(\d+)(?:\.(\d+)|)(?:\.(\d+]]
            .. [[)|)|)]],
}

local function match_user_agent(user_agent, conf)
    user_agent = str_strip(user_agent)
    if conf.whitelist then
        for _, rule in ipairs(conf.whitelist) do
            if re_find(user_agent, rule, "jo") then
                return MATCH_ALLOW
            end
        end
    end

    if conf.blacklist then
        for _, rule in ipairs(conf.blacklist) do
            if re_find(user_agent, rule, "jo") then
                return MATCH_DENY
            end
        end
    end

    for _, rule in ipairs(well_known_bots) do
        if re_find(user_agent, rule, "jo") then
            return MATCH_BOT
        end
    end

    return MATCH_NONE
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end

function _M.access(conf, ctx)
    local user_agent = core.request.header(ctx, "User-Agent")

    if not user_agent then
        return
    end
    -- ignore multiple instances of request headers
    if type(user_agent) == "table" then
        return
    end
    local match, err = lrucache_useragent(user_agent, conf, match_user_agent, user_agent, conf)
    if err then
        return
    end

    if match > MATCH_ALLOW then
        return 403, { message = conf.message }
    end
end

return _M
