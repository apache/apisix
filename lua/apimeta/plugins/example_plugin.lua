local plugin = require("apimeta.plugin")


local args_schema = {
    i = "int",          -- value list: apimeta.core.typeof#92
    s = "string",
    t = "table",
}


local _M = {version = 0.1}


function _M.check_args(config)
    local ok, err = plugin.check_args(config, args_schema)
    if not ok then
        return false, err
    end

    -- add more restriction rules if we needs

    return true
end


function _M.init(config)
    plugin.log.warn("plugin init")

    local ok, err = _M.check_args(config)
    if not ok then
        return false, err
    end

    return true
end


function _M.rewrite(ctx)
    plugin.log.warn("plugin rewrite phase")
    return true
end

return _M
