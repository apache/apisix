local core = require("apisix.core")

local plugin_name = "cmd-args-to-ctx"

local schema = {
    type = "object",
    properties = {
        args = {
            type = "object",
            description = "specify args need to parse"
        }
    }
}

local _M = {
    version = 0.1,
    priority = 1001,   
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

    for arg_name, arg_value in pairs(conf.args) do 
        ctx.var[arg_name] = arg_value
	core.log.error("-----", arg_name, "----", arg_value)
    end
end

return _M
