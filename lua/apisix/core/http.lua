local fetch_local_conf = require("apisix.core.config_local").local_conf
-- local log = require("apisix.core.log")
-- local json = require("apisix.core.json")
local http = require("resty.http")


local _M = {
    version = 0.1,
}


function _M.request_self(uri, opts)
    local local_conf = fetch_local_conf()
    if not local_conf or not local_conf.apisix
       or not local_conf.apisix.node_listen then
        return nil, nil -- invalid local yaml config
    end

    local httpc = http.new()
    local full_uri = "http://127.0.0.1:" .. local_conf.apisix.node_listen
                     .. uri
    return httpc:request_uri(full_uri, opts)
end


return _M
