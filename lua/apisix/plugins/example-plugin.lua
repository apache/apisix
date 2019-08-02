local core = require("apisix.core")
local balancer = require("ngx.balancer")

-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
local schema = {
    type = "object",
    properties = {
        i = {type = "number", minimum = 0},
        s = {type = "string"},
        t = {type = "array", minItems = 1},
        ip = {type = "string"},
        port = {type = "integer"},
    },
    required = {"i"},
}


local plugin_name = "example-plugin"

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


function _M.rewrite(conf, ctx)
    core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf))
    -- core.log.warn(" ctx: ", core.json.encode(ctx, true))
end


function _M.access(conf, ctx)
    core.log.warn("plugin access phase, conf: ", core.json.encode(conf))
    -- return 200, {message = "hit example plugin"}
end


function _M.balancer(conf, ctx)
    core.log.warn("plugin access phase, conf: ", core.json.encode(conf))

    if not conf.ip then
        return
    end

    -- NOTE: update `ctx.balancer_name` is important, APISIX will skip other
    -- balancer handler.
    ctx.balancer_name = plugin_name

    local ok, err = balancer.set_current_peer(conf.ip, conf.port)
    if not ok then
        core.log.error("failed to set server peer: ", err)
        return core.response.exit(502)
    end
end


return _M
