--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
--
local http = require("resty.http" )
local core = require("apisix.core")

local _M = {}
local mt = { __index = _M }

function _M.new(opts)
    return setmetatable(opts or {}, mt)
end

function _M:request(url, body, headers, timeout)
    local httpc = http.new( )
    if timeout then
        httpc:set_timeout(timeout )
    end

    local res, err = httpc:request_uri(url, {
        method = "POST",
        body = core.json.encode(body ),
        headers = headers,
        ssl_verify = false,
    })

    if not res then
        return nil, "failed to request AI provider: " .. err
    end

    return res
end

return _M
