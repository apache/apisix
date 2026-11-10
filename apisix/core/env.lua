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

local ENV_PREFIX = "$ENV://"

local _M = {
    PREFIX = ENV_PREFIX
}


local apisix_env_vars = {}

ffi.cdef [[
  extern char **environ;
]]


-- Build an exact-keyed table from the process environment (`environ`).
--
-- This is intentionally used instead of `os.getenv` to sidestep a bug in
-- lua-resty-core's `os.getenv` shim that is active before any request is
-- being served (init / init_worker phases). That shim relies on
-- `ngx_http_lua_ffi_get_conf_env`, which matches an `env NAME=VALUE;`
-- directive entry against the queried name with a prefix-only comparison
-- (`ngx_strncmp(name, var.data, var.len)`) and does not require the queried
-- name to end at `var.len`. As a result, when two `env` directives share a
-- common prefix (e.g. `KUBERNETES_CLIENT_TOKEN` and
-- `KUBERNETES_CLIENT_TOKEN_FILE`), the shorter declared name shadows the
-- longer one. Reading `environ` directly and keying by the substring before
-- the first `=` avoids the collision entirely. See apache/apisix#13055.
--
-- Note on phases: nginx applies `env NAME=VALUE;` directives to the real
-- `environ` in `ngx_set_environment`, which runs at worker process start
-- (before `init_worker_by_lua`). Therefore `init()` must be called again in
-- the worker init phase so that directive-assigned values are captured; at
-- the `init_by_lua` phase `environ` only contains variables inherited from
-- the OS, not the directive-assigned ones.
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


-- Look up an environment variable by exact name.
--
-- Prefer the snapshot built by `init()` (immune to the prefix-collision bug
-- described above) and only fall back to `os.getenv` for variables that were
-- set dynamically after startup (e.g. via `core.os.setenv`).
function _M.get(name)
    local val = apisix_env_vars[name]
    if val ~= nil then
        return val
    end

    return os.getenv(name)
end


local function parse_env_uri(env_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    if type(env_uri) ~= "string" then
        return nil, "error env_uri type: " .. type(env_uri)
    end

    if not string.has_prefix(upper(env_uri), ENV_PREFIX) then
        return nil, "error env_uri prefix: " .. env_uri
    end

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


function _M.fetch_by_uri(env_uri)
    log.info("fetching data from env uri: ", env_uri)
    local opts, err = parse_env_uri(env_uri)
    if not opts then
        return nil, err
    end

    local main_value = _M.get(opts.key)
    if main_value and opts.sub_key ~= "" then
        local vt, err = json.decode(main_value)
        if not vt then
            return nil, "decode failed, err: " .. (err or "") .. ", value: " .. main_value
        end
        return vt[opts.sub_key]
    end

    return main_value
end


return _M
