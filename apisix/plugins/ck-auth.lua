local core = require("apisix.core")

local plugin_name = "ck-auth"
local status_codes = {
    200, 401
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
local function responseBody(status_code, message)
    return status_code, {
        status_code = status_code,
        message = message,
        data = nil
    }
end

function _M.rewrite(conf, ctx)
    core.log.info("rewrite")
    local auth_token = core.request.header(ctx, "ck")
    if not auth_token then
        return responseBody(status_codes[2], "没有在header里面传入程锟的插件认证关键参数")
    end
    return responseBody(status_codes[1], auth_token)
end


return _M