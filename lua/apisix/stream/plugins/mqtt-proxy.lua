local core = require("apisix.core")

local schema = {
    type = "object",
    properties = {
        protocol_name = {type = "string"},
        protocol_level = {type = "integer"},
        upstream = {
            type = "object",
            properties = {
                ip = {type = "string"},
                port = {type = "number"},
            }
        }
    },
    required = {"protocol_name", "protocol_level", "upstream"},
}


local plugin_name = "mqtt-proxy"


local _M = {
    version = 0.1,
    priority = 0,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


function _M.preread(conf, ctx)
    core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf))
    -- core.log.warn(" ctx: ", core.json.encode(ctx, true))
end


function _M.log(conf, ctx)
    core.log.warn("plugin log phase, conf: ", core.json.encode(conf))
end


return _M
