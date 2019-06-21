local core = require("apisix.core")

local _M = {
    version = 0.1,
}


function _M.get(name)
    local json_schema = core.schema[name]
    if not json_schema then
        return 400, {error_msg = "not found schema"}
    end

    return 200, json_schema
end


return _M
