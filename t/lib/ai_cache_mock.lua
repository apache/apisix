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

--- Mock embeddings upstream for the ai-cache semantic (L2) tests.
-- Replays the real text-embedding-3-small responses captured (at dimensions=64)
-- under t/fixtures/openai/embeddings-*.json, selecting one by the request prompt
-- so the suite exercises genuine embedding geometry without calling OpenAI:
--   "...capital city..." -> capital_city   "...capital..." -> capital
--   "...largest..."      -> largest_city   "...tire..."    -> tire

local fixture_loader = require("lib.fixture_loader")
local cjson          = require("cjson.safe")

local ngx  = ngx
local type = type

local _M = {}

local FIXTURE = {
    capital      = "openai/embeddings-capital.json",
    capital_city = "openai/embeddings-capital-city.json",
    largest_city = "openai/embeddings-largest-city.json",
    tire         = "openai/embeddings-tire.json",
}


local function serve(name)
    local content, err = fixture_loader.load(name)
    if not content then
        ngx.status = 500
        ngx.say(err or "fixture not found")
        return
    end
    ngx.print(content)
end


-- Pick the embedding fixture the request is asking about. "capital city" is
-- checked before "capital" so the paraphrase stays distinct from the anchor.
local function pick(input)
    if input:find("largest", 1, true) then
        return FIXTURE.largest_city
    elseif input:find("tire", 1, true) then
        return FIXTURE.tire
    elseif input:find("capital city", 1, true) then
        return FIXTURE.capital_city
    elseif input:find("capital", 1, true) then
        return FIXTURE.capital
    end
    return FIXTURE.tire   -- default: an unrelated/orthogonal vector
end


-- Prompt-keyed embeddings endpoint used by the end-to-end semantic tests.
function _M.embeddings()
    ngx.req.read_body()
    local body  = cjson.decode(ngx.req.get_body_data() or "{}") or {}
    local input = type(body.input) == "string" and body.input or ""
    serve(pick(input))
end


-- openai driver unit mock: must carry Authorization: Bearer.
function _M.embeddings_openai()
    if ngx.req.get_headers()["authorization"] ~= "Bearer test-key" then
        ngx.status = 401
        ngx.say("bad authorization")
        return
    end
    serve(FIXTURE.capital)
end


-- azure_openai driver unit mock: must carry the api-key header, never Authorization.
function _M.embeddings_azure()
    if ngx.req.get_headers()["api-key"] ~= "test-key" then
        ngx.status = 401
        ngx.say("missing api-key header")
        return
    end
    if ngx.req.get_headers()["authorization"] then
        ngx.status = 400
        ngx.say("azure driver must not send Authorization")
        return
    end
    serve(FIXTURE.capital)
end


-- First hit: 200 + SSE headers then stall (read timeout, no body); later hits serve the fixture.
local flaky_hits = 0
function _M.chat_flaky_once()
    flaky_hits = flaky_hits + 1
    if flaky_hits == 1 then
        ngx.header["Content-Type"] = "text/event-stream"
        ngx.send_headers()
        ngx.flush(true)
        ngx.sleep(2)
        return
    end
    fixture_loader.dispatch()
end


-- always 5xx: drives the embedding-provider fail-open path.
function _M.broken()
    ngx.status = 500
    ngx.say("embedding upstream error")
end


-- well-formed HTTP 200 but a body the driver must reject.
function _M.malformed()
    ngx.say('{"data":[]}')
end


return _M
