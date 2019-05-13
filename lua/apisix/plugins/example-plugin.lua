local apisix = require("apisix")
local base_plugin = apisix.base_plugin


-- TODO: need a more powerful way to define the schema
local args_schema = {
    i = "int",
    s = "string",
    t = "table",
}


local _M = {
    version = 0.1,
    priority = 1000,        -- TODO: add a type field, may be a good idea
    name = "example-plugin",
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
    apisix.log.warn("plugin rewrite phase")
end


function _M.access(conf)
    apisix.log.warn("plugin access phase")
    ngx.say("hit example access phase")
end


return _M
