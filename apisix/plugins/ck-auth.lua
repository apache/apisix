local core = require("apisix.core")

local plugin_name = "ck-auth"

local schema = {
    type = "object",
    properties = {
        king = {
            type = "string",
            enum = { "ck" }
        }
    },
    required = { "king" }
}

local _M = {
    version = 0.1,
    priority = 90,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- 入口
function _M.access(conf, ctx)

    core.log.warn(core.json.encode(conf))

end

return _M