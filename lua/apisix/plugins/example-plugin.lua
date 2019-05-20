local core = require("apisix.core")
local base_plugin = require("apisix.base_plugin")


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
    local ok, err = base_plugin.check_args(conf, args_schema)
    if not ok then
        return false, err
    end

    -- add more restriction rules if we needs

    return true
end


function _M.rewrite(conf, api_ctx)
    core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf),
                  " ctx: ", core.json.encode(api_ctx, true))
end


function _M.access(conf, api_ctx)
    core.log.warn("plugin access phase, conf: ", core.json.encode(conf),
                  " ctx: ", core.json.encode(api_ctx, true))
    -- ngx.say("hit example plugin")
end


return _M
