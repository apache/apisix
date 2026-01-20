-- AI driver base module
-- AI 驱动基类模块
local core = require("apisix.core")
local http = require("resty.http" )
local json = require("apisix.core.json")

-- Module table and metatable
-- 模块表和元表
local _M = {}
local mt = { __index = _M }

-- Create a new driver instance
-- 创建一个新的驱动实例
-- opts: table containing `name` and `conf` fields
function _M.new(opts)
    local self = {
        name = opts.name,
        conf = opts.conf,
    }
    return setmetatable(self, mt)
end

-- Common HTTP request logic for AI drivers
-- 通用的 HTTP 请求逻辑，供各 AI 驱动复用
-- Params:
-- - self: driver instance
-- - url: target URL for the request
-- - body: Lua table payload to be JSON-encoded
-- - headers: table of HTTP headers
function _M.request(self, url, body, headers)
    local httpc = http.new( )
    local res, err = httpc:request_uri(url, {
        method = "POST",
        body = json.encode(body ),
        headers = headers,
        keepalive_timeout = 60000,
        keepalive_pool = 10
    })

    if not res then
        return nil, "failed to request: " .. err
    end

    return res
end

-- Return the module
-- 返回模块表
return _M
