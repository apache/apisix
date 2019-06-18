local core = require("apisix.core")
local tostring = tostring


local _M = {
    version = 0.1,
}


local function check_conf(uri_segs, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    local id = uri_segs[5]
    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing upstream id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong upstream id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong upstream id"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.upstream))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.upstream, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if conf.type == "chash" and not conf.key then
        return nil, {error_msg = "missing key"}
    end

    return need_id and id or true
end


function _M.put(uri_segs, conf)
    local id, err = check_conf(uri_segs, conf, true)
    if not id then
        return 400, err
    end

    local key = "/upstreams/" .. id
    core.log.info("key: ", key)
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(uri_segs)
    local id = uri_segs[5]
    local key = "/upstreams"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(uri_segs, conf)
    local id, err = check_conf(uri_segs, conf, false)
    if not id then
        return 400, err
    end

    local key = "/upstreams"
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(uri_segs)
    -- todo: need to check if any route or service is still using this
    --     upstream now.
    local id = uri_segs[5]
    if not id then
        return 400, {error_msg = "missing upstream id"}
    end

    local key = "/upstreams/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
