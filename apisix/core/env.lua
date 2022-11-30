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
local ffi         = require "ffi"

local json        = require("apisix.core.json")
local log         = require("apisix.core.log")
local string      = require("apisix.core.string")

local os          = os
local type        = type
local upper       = string.upper
local find        = string.find
local sub         = string.sub
local str         = ffi.string

local _M = {}

local ENV_PREFIX = "$ENV://"

local apisix_env_vars = {}

ffi.cdef [[
  extern char **environ;
]]


function _M.init()
  local e = ffi.C.environ
  if not e then
    log.warn("could not access environment variables")
    return
  end

  local i = 0
  while e[i] ~= nil do
    local var = str(e[i])
    local p = find(var, "=")
    if p then
        apisix_env_vars[sub(var, 1, p - 1)] = sub(var, p + 1)
    end

    i = i + 1
  end
end


local function is_env_uri(env_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    return type(env_uri) == "string" and string.has_prefix(upper(env_uri), ENV_PREFIX)
end


local function parse_env_uri(env_uri)
    local path = sub(env_uri, #ENV_PREFIX + 1)
    local idx = find(path, "/")
    if not idx then
        return {key = path, sub_key = ""}
    end
    local key = sub(path, 1, idx - 1)
    local sub_key = sub(path, idx + 1)

    return {
      key = key,
      sub_key = sub_key
    }
end


function _M.get(env_uri)
    if not is_env_uri(env_uri) then
        return nil
    end

    local opts = parse_env_uri(env_uri)
    local main_value = apisix_env_vars[opts.key] or os.getenv(opts.key)
    if main_value and opts.sub_key ~= "" then
        local vt, err = json.decode(main_value)
        if not vt then
          log.warn("decode failed, err: ", err, " value: ", main_value)
          return nil
        end
        return vt[opts.sub_key]
    end

    return main_value
end


return _M
