local core = require "apisix.core"

local plugin_name = "path-key-extractor"

local schema = {
    type = "object",
    properties = {
        regex = { type = "string", default = "v1/(%w+)" }
    },
    required = { "regex" },
}


local _M = {
    version = 0.1,
    priority = 2501,
    name = plugin_name,
    schema = schema,
}

function _M.rewrite(conf)
    -- Extract the apikey parameter from the request path using the specified regex
    local api_key = string.match(ngx.var.uri, conf.regex)

    -- Set the apikey to the request header
    ngx.req.set_header("apikey", api_key)
end

return _M
