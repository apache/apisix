local core = require("apisix.core")
local plugin_name = "proxy-rewrite"
local ipairs = ipairs
local str_gsub = string.gsub

local schema = {
    type = "object",
    properties = {

    },
}

local _M = {
    version = 0.1,
    priority = 1008,
    name = plugin_name,
    schema = schema,
}

local upstream_vars = {
    uri        = "upstream_uri",
    scheme     = "upstream_scheme",
    host       = "upstream_host",
    upgrade    = "upstream_upgrade",
    connection = "upstream_connection",
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

function _M.rewrite(conf, ctx)
    local ngx_var = ngx.var
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx
    core.log.info("------------access-proxy-rewrite-ctx: ", core.json.delay_encode(ctx, true))
    core.log.info("------------access-proxy-rewrite-conf: ", core.json.delay_encode(conf, true))
    local new_uri = str_gsub(conf.uri, '{id}', 1001)
    core.log.info("------------access-proxy-rewrite-new-uri: ", new_uri)
    core.log.info("------------access-proxy-rewrite-enable: ", conf.enable_websocket)
    core.log.info("------------conf-length: ", table.maxn(conf))
    ngx.req.set_uri(new_uri)

    for _, name in ipairs(conf) do
        if conf[name] then
            ngx_var[upstream_vars[name]] = conf[name]
        end
    end

    if conf.enable_websocket then
        api_ctx.var["upstream_upgrade"] = api_ctx.var["http_upgrade"]
        api_ctx.var["upstream_connection"] = api_ctx.var["http_connection"]
    end
end

function _M.access(conf, ctx)
    --
end

return _M
