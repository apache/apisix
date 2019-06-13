return function(plugin_name, priority)
    local core = require("apisix.core")

    local schema = {
        type = "object",
        properties = {
            functions = {type = "array", items = {type = "string"}, minItems = 1},
        },
        required = {"functions"}
    }

    local _M = {
        version = 0.1,
        priority = priority,
        name = plugin_name,
    }

    function _M.check_schema(conf)
        local ok, err = core.schema.check(schema, conf)
        if not ok then
            return false, err
        end

        return true
    end

    function _M.access(conf, ctx)
        ngx.log(ngx.ERR, conf.functions)
    end

    return _M
end
