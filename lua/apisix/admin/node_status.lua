local core = require("apisix.core")


local _M = {
    version = 0.1,
}


function _M.get(id)
    local key = "/node_status"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
