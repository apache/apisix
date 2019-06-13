local core = require("apisix.core")
local _M = {version = 0.1}


function _M.put(uri_segs, data)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 200, {error_msg = "missing route id"}
    end

    local key = "/" .. resource .. "/" .. id
    local res, err = core.etcd.set(key, data)
    if not res then
        core.log.error("failed to get routes[", key, "]: ", err)
        return 500
    end

    return res.status, res.body
end


function _M.get(uri_segs)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 200, {error_msg = "missing route id"}
    end

    local key = "/" .. resource .. "/" .. id
    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get routes[", key, "]: ", err)
        return 500
    end

    return res.status, res.body
end


function _M.post(uri_segs, data)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 200, {error_msg = "missing route id"}
    end

    local key = "/" .. resource .. "/" .. id
    local res, err = core.etcd.push(key, data)
    if not res then
        core.log.error("failed to get routes[", key, "]: ", err)
        return 500
    end

    return res.status, res.body
end


return _M
