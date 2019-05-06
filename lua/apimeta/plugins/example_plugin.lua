local typeof = require("apimeta.comm.typeof")


local args_schema = {
    i = "int",          -- value list: apimeta.comm.typeof#92
    s = "string",
    t = "table",
}


local _M = {VER = 0.1}


function _M.check_args(config)
    local ok, err = typeof.comp_tab(config, args_schema)
    if not ok then
        return err
    end

    -- add more restriction rules if we needs

    return true
end


function _M.init(config)
    local ok, err = _M.check_args(config)
    if not ok then
        return ok, err
    end

    return true
end

return _M
