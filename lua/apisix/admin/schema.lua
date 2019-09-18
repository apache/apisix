local core = require("apisix.core")

local _M = {
    version = 0.1,
}


function _M.get(name)
    local json_schema = core.schema[name]
    core.log.info("schema: ", core.json.delay_encode(core.schema, true))
    if not json_schema then
        return 400, {error_msg = "not found schema: " .. name}
    end

    return 200, json_schema
end


return _M
