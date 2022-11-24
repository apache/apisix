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
local C           = ffi.C

local _M = {}

local ENV_PREFIX = "$ENV://"

local apisix_env_vars = {}

ffi.cdef [[
  extern char **environ;
  int memcmp(const void *s1, const void *s2, size_t n);
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


local function is_env_ref(ref)
    -- We will not use string.has_prefix,
    -- to avoid the error caused by has_prefix to cause a crash.
    return type(ref) == "string" and #ref > 7 and
        0 == C.memcmp(upper(ref), ENV_PREFIX, 7)
end


local function parse_ref(ref)
    local path = sub(ref, 8)
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


function _M.get(ref)
    if not is_env_ref(ref) then
        return nil
    end

    local opts = parse_ref(ref)
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
