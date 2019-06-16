local core = require("apisix.core")
local tostring = tostring


local _M = {
    version = 0.1,
}


function _M.put(uri_segs, conf)
    local id = uri_segs[5]
    id = id or tostring(conf.id)
    if conf.id and tostring(conf.id) ~= id then
        return 400, {error_msg = "wrong service id"}
    end

    if not id then
        return 400, {error_msg = "missing service id"}
    end

    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.service))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.service, conf)
    core.log.info("ok: ", ok, " err: ", err)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local key = "/services/" .. id
    core.log.info("key: ", key)
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(uri_segs)
    local id = uri_segs[5]
    local key = "/services"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(uri_segs, conf)
    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.service))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.service, conf)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local key = "/services"
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(uri_segs)
    local id = uri_segs[5]
    if not id then
        return 400, {error_msg = "missing service id"}
    end

    local key = "/services/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
