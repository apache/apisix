local core = require("apisix.core")
local base_plugin = require("apisix.base_plugin")
local encode_json = require("cjson.safe").encode


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


function _M.rewrite(conf)
    core.log.warn("plugin rewrite phase, conf: ", encode_json(conf))
end


function _M.access(conf)
    core.log.warn("plugin access phase, conf: ", encode_json(conf))
    -- ngx.say("hit example plugin")
end


return _M
