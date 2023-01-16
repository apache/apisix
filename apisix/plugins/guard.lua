local core  = require("apisix.core")
local ngx   = ngx
local cjson = require("cjson")


local schema = {
    type = "object",
    properties = {
        error_code = {
            description = "HTTP status code to return to the client",
            type = "integer",
            minimum = 100,
            maximum = 599,
            default = 403,
        },
        error_message = {
            description = "error message to return to the client",
            type = "object",
            properties = {
                jsonrpc = {
                    description = "JSON-RPC version",
                    type = "string",
                    default = "2.0",
                },
                error = {
                    description = "error object",
                    type = "object",
                    properties = {
                        code = {
                            description = "error code",
                            type = "integer",
                            minimum = -32768,
                            maximum = 32767,
                            default = -32603,
                        },
                        message = {
                            description = "error message",
                            type = "string",
                            default = "Invalid Request",
                        },
                    },
                    required = { "code", "message", },
                },
            },
        },
    },
}

local plugin_name = "guard"

local _M = {
    version = 0.1,
    priority = 50,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

function _M.access(conf, ctx)
    -- Block all requests
    ngx.header["Content-Type"] = "application/json"
    return core.response.exit(conf.error_code, cjson.encode(conf.error_message))
end

return _M
