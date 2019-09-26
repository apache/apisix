local core        = require("apisix.core")
local plugin_name = "proxy-rewrite"
local pairs       = pairs
local ipairs      = ipairs

local schema = {
    type = "object",
    properties = {
        uri = {
            type = "string"
        },
        host = {
            type = "string"
        },
        scheme = {
            type    = "string",
            enum    = {"http", "https"}
        },
        enable_websocket = {
            type = "boolean",
            default = false
        }
    },
}

local _M = {
    version  = 0.1,
    priority = 1008,
    name     = plugin_name,
    schema   = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end

do
    local upstream_vars = {
        uri        = "upstream_uri",
        scheme     = "upstream_scheme",
        host       = "upstream_host",
        upgrade    = "upstream_upgrade",
        connection = "upstream_connection",
    }
    local upstream_names = {}
    for name, _ in pairs(upstream_vars) do
        core.table.insert(upstream_names, name)
    end

function _M.rewrite(conf, ctx)
    for _, name in ipairs(upstream_names) do
        if conf[name] then
            ctx.var[upstream_vars[name]] = conf[name]
        end
    end

    if conf.enable_websocket then
        ctx.var["upstream_upgrade"]    = ctx.var["http_upgrade"]
        ctx.var["upstream_connection"] = ctx.var["http_connection"]
    end
end

end  -- do

return _M
