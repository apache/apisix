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

--- Test fixture loader for AI proxy mock responses.
-- Loads fixture files from t/fixtures/ and serves them based on the
-- X-AI-Fixture request header.
--
-- Supported headers:
--   X-AI-Fixture: <path>          -- fixture file path relative to t/fixtures/
--   X-AI-Fixture-Status: <code>   -- optional HTTP status code (default 200)

local _M = {}
local io = io
local ngx = ngx

local fixture_base_dir


local function get_fixture_dir()
    if fixture_base_dir then
        return fixture_base_dir
    end

    local constants = require("apisix.constants")
    local lua_home = constants and constants.apisix_lua_home
    if type(lua_home) ~= "string" or lua_home == "" then
        return nil, "apisix_lua_home is not initialized"
    end
    fixture_base_dir = lua_home .. "/t/fixtures/"
    return fixture_base_dir
end


function _M.load(name)
    if type(name) ~= "string" or #name == 0 or #name > 256 then
        return nil, "invalid fixture name"
    end
    if name:sub(1, 1) == "/" or name:find("..", 1, true) then
        return nil, "invalid fixture name"
    end
    if not name:match("^[%w%._/-]+$") then
        return nil, "invalid fixture name"
    end

    local dir, dir_err = get_fixture_dir()
    if not dir then
        return nil, dir_err
    end
    local path = dir .. name
    local f = io.open(path, "r")
    if not f then
        return nil, "fixture not found"
    end
    local content, read_err = f:read("*a")
    local ok, close_err = f:close()
    if not content then
        return nil, "failed to read fixture: " .. (read_err or "unknown error")
    end
    if not ok then
        return nil, "failed to close fixture: " .. (close_err or "unknown error")
    end
    return content
end


-- Replace {{model}} placeholder with the model from request body.
local function apply_template(content)
    if not content:find("{{model}}", 1, true) then
        return content
    end

    ngx.req.read_body()
    local body_data = ngx.req.get_body_data()
    if not body_data then
        return content:gsub("{{model}}", "unknown")
    end

    local json = require("cjson.safe")
    local body = json.decode(body_data)
    if not body or not body.model then
        return content:gsub("{{model}}", "unknown")
    end

    return content:gsub("{{model}}", body.model)
end


-- Serve a fixture based on the X-AI-Fixture request header.
-- For .sse files: sets Content-Type to text/event-stream and sends content as-is.
-- For other files: sets Content-Type to application/json.
-- Optional X-AI-Fixture-Status header overrides the HTTP status code.
function _M.dispatch()
    local headers = ngx.req.get_headers()
    local fixture_name = headers["x-ai-fixture"]
    if not fixture_name then
        ngx.status = 400
        ngx.say("missing X-AI-Fixture header")
        return
    end

    local content, err = _M.load(fixture_name)
    if not content then
        ngx.status = 500
        ngx.say(err)
        return
    end

    content = apply_template(content)

    local status = tonumber(headers["x-ai-fixture-status"])
    if status then
        ngx.status = status
    end

    if fixture_name:match("%.sse$") then
        ngx.header["Content-Type"] = "text/event-stream"
        ngx.header["Cache-Control"] = "no-cache"
        ngx.header["Transfer-Encoding"] = "chunked"
        ngx.print(content)
        ngx.flush(true)
    else
        ngx.header["Content-Type"] = "application/json"
        ngx.print(content)
    end
end


return _M
