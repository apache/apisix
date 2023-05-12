local plugin_name = "cmd-args-to-ctx"

local schema = {
    type = "object",
    properties = {
        args = {
            type = "object",
            description = "specify args need to parse from command line"
        }
    }
}

local _M = {
    version = 0.1,
    priority = 23001,   -- higher than traffic-split
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    if not conf or not conf.args then
        return
    end

    for arg_name, arg_key in pairs(conf.args) do
        local arg_value = core.cmd_var.get(arg_name)
        if arg_value then
            ctx.var[arg_key] = arg_value
        end
    end 
end

return _M