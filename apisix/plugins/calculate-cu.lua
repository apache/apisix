local core = require "apisix.core"

local plugin_name = "calculate-cu"

local schema = {
    type = "object",
    properties = {
        methods = {
            type = "object",
            patternProperties = {
                ["^[a-zA-Z_][a-zA-Z0-9_]*$"] = { type = "integer", minimum = 1 }
            }
        }
    },
}

local _M = {
    version = 0.1,
    priority = 1012,
    name = plugin_name,
    schema = schema,
}

function _M.access(conf, ctx)
    -- Check if it's a batch request
    local method = ctx.var["jsonrpc_method"]
    if method == "batch" then
        -- Calculate cu for each method in the batch request
        local methods = ctx.var["jsonrpc_methods"]
        if methods then
            local cu = 0
            for _, m in ipairs(methods) do
                cu = cu + (conf.methods[m] or 1)
            end
            ctx.var["cu"] = cu
        else
            return 400, { error_msg = "Invalid JSON-RPC request" }
        end
    else
        -- Calculate cu for a single request
        ctx.var["cu"] = conf.methods and conf.methods[method] or 1
    end
end

return _M
