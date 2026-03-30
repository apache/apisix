-- Stream route gating plugin for APISIX.
--
-- Attach to any stream route to control whether it accepts connections.
-- When the "active" flag is truthy, traffic flows normally; otherwise
-- connections are refused with an optional rejection message.
--
-- -----------------------------------------------------------------------------------------------------
-- Note: This plugin operates at the stream level, so it does not have
-- access to HTTP-specific features like status codes or headers. Instead,
-- it simply accepts or rejects TCP/TLS connections based on the "enabled" flag.
-- ----------------------------------------------------------------------------------------------------
--
-- Usage example:
-- 1. Enable the plugin on a stream route:
--    curl -X PUT http://<APISIX_HOST>:<APISIX_PORT>/apisix/admin/stream_routes/<STREAM_ROUTE_ID> \
--         -H "X-API-KEY: ${admin_key}" \
--         -H "Content-Type: application/json" \
--         -d '{
--               "plugins": {
--                 "sr-enable-disable": {
--                   "enabled": true,
--                   "decline_msg": "Stream route is currently disabled."
--                 }
--               },
--               "upstream": {
--                 "type": "roundrobin",
--                 "nodes": {
--                   "<NODE_ADDRESS>:<PORT>": 1
--                 }
--               }
--             }'
-- 2. Toggle the "enabled" flag to control access:
--    - To disable: set "enabled" to false.
--    - To enable: set "enabled" to true.
-----------------------------------------------------------------------------------------------------

local pcall      = pcall
local log        = require("apisix.core").log
local checker    = require("apisix.core").schema

local NAME = "sr-enable-disable"
local DEFAULT_REJECTION = "Stream route in disabled state."

local conf_schema = {
    type = "object",
    properties = {
        enabled = {
            type = "boolean",
            default = false,
        },
        decline_msg = {
            type = "string",
            default = DEFAULT_REJECTION,
        },
    },
    required = {"enabled"},
    additionalProperties = false,
}

local _M = {
    version  = 1.0,
    priority = 10000,
    name     = NAME,
    schema   = conf_schema,
}


function _M.check_schema(conf)
    return checker.check(conf_schema, conf)
end


local function reject_connection(reason)
    local sock, err = ngx.req.socket()
    if not sock then
        log.error(NAME, ": failed to get downstream socket: ", err)
        return
    end

    sock:send(reason .. "\n")
    sock:close()
end


function _M.preread(conf, ctx)
    if conf.enabled then
        return            -- route is active, let it through
    end

    local reason = conf.decline_msg or DEFAULT_REJECTION
    log.warn(NAME, ": refusing stream connection - ", reason)

    reject_connection(reason)

    return 503
end


return _M
