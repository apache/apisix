local core = require("apisix.core")
local routes = require("apisix.http.route").routes
local schema_plugin = require("apisix.admin.plugins").check_schema
local tostring = tostring
local ipairs = ipairs
local tonumber = tonumber


local _M = {
    version = 0.1,
}

function _M.post(conf)
	--todo check hash to confirm config is changed
	--todo parse config
	
	--todo load config into cache
	--todo create/raise events
    return 200, "ok"
end


return _M