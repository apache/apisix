local core = require("apisix.core")

local plugin_name = "ck-auth"
local status_codes = {
    success = 200,
    error = 400
}
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

function _M.access(conf, ctx)

    core.log.info("access")

end

-- 返回参数的固定格式
local function responseBody(status_code, message, data)
    return status_code, {
        status_code = status_code,
        message = message,
        data = data
    }
end

function _M.rewrite(conf, ctx)
    core.log.info("rewrite")
    local auth_token = core.request.header(ctx, "ck")
    local data = {
        request = {
            host = core.request.get_host(ctx),
            http_version = core.request.get_http_version(),
            ip = core.request.get_ip(ctx),
            port = core.request.get_port(ctx),
            remote_client_ip = core.request.get_remote_client_ip(ctx),
            remote_client_port = core.request.get_remote_client_port(ctx),
            scheme = core.request.get_scheme(ctx),
            uri_args = core.request.get_uri_args(ctx),
            headers = core.request.headers()
        },
        response = {
            upstream_status = core.response.get_upstream_status(ctx)
        }
    }
    if not auth_token then
        return responseBody(status_codes.error, "没有在header里面传入程锟的插件认证关键参数", data)
    end
    return responseBody(status_codes.success, auth_token, data)
end


return _M