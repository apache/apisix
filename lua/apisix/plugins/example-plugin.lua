local core = require("apisix.core")


-- TODO: need a more powerful way to define the schema
local args_schema = {
    i = "int",
    s = "string",
    t = "table",
}


local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 1000,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_args(conf)
    local ok, err = core.schema.check_args(conf, args_schema)
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
    -- core.log.warn(" ctx: ", core.json.encode(ctx, true))
    ngx.say("hit example plugin")
end


return _M
