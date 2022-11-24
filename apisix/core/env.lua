local ffi = require "ffi"

local os = os
local type = type
local upper = string.upper
local find = string.find
local sub = string.sub
local str = ffi.string

local json = require("apisix.core.json")
local log  = require("apisix.core.log")

local _M = {}

local ENV_PREFIX = "$ENV://"

if not _G._apisix_env_vars then
    _G._apisix_env_vars = {}
end

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
        _apisix_env_vars[sub(var, 1, p - 1)] = sub(var, p + 1)
    end

    i = i + 1
  end
end


local function is_env_ref(ref)
    return type(ref) == "string" and sub(upper(ref), 1, 7) == ENV_PREFIX
end


local function parse_ref(ref)
    local path = sub(ref, 8)
    local idx = find(path, "/")
    if not idx then
        return path, ""
    end
    local key = sub(path, 1, idx - 1)
    local sub_key = sub(path, idx + 1)

    return key, sub_key
end


function _M.get(ref)
    if not is_env_ref(ref) then
        return nil
    end

    local key, sub_key = parse_ref(ref)
    local main_value = _apisix_env_vars[key] or os.getenv(key)
    if main_value and sub_key ~= "" then
        local vt = json.decode(main_value)
        if not vt then
            return nil
        end
        return vt[sub_key]
    end

    return main_value
end


return _M