local config_local = require("apisix.core.config_local")
local etcd_util = require("apisix.utils.etcd")
local _M = {}

-- TODO: register this function as a handler for new status endpoint
-- in ngx_tpl.lua

function _M.status()
    local res_init_err = ngx.shared["res_init_err"]
    local err = res_init_err:get("err")
    if err then
        return 503
    end

    local yaml_conf = config_local.local_conf()
    local unhealthy_etcd_count = 0
    for _, host in ipairs(yaml_conf.etcd.host) do
        local res = etcd_util.request(host .. "/version", yaml_conf)
        if not res then
            unhealthy_etcd_count = unhealthy_etcd_count + 1
        end
    end

    if unhealthy_etcd_count > 1 then
        return 503
    end

    return 200
end

return _M
