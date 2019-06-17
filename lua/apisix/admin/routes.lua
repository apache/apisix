local core = require("apisix.core")
local schema_plugin = require("apisix.admin.plugins").check_schema
local tostring = tostring


local _M = {
    version = 0.1,
}


function _M.put(uri_segs, conf)
    local resource, id = uri_segs[4], uri_segs[5]
    id = id or tostring(conf.id)
    if conf.id and tostring(conf.id) ~= id then
        return 400, {error_msg = "wrong route id"}
    end

    if not id then
        return 400, {error_msg = "missing route id"}
    end

    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    -- core.log.info("schema: ", core.schema.route)
    -- core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.route, conf)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local service_id = conf.service_id
    if service_id then
        local key = "/services/" .. service_id
        local res, err = core.etcd.get(key)
        if not res then
            return 400, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return 400, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    local upstream_id = conf.upstream_id
    if upstream_id then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return 400, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return 400, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return 400, {error_msg = err}
        end
    end

    local key = "/" .. resource .. "/" .. id
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(uri_segs)
    local resource, id = uri_segs[4], uri_segs[5]
    local key = "/" .. resource
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


function _M.post(uri_segs, conf)
    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    local ok, err = core.schema.check(core.schema.route, conf)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local service_id = conf.service_id
    if service_id then
        local key = "/services/" .. service_id
        local res, err = core.etcd.get(key)
        if not res then
            return 400, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return 400, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    local upstream_id = conf.upstream_id
    if upstream_id then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return 400, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return 400, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return 400, {error_msg = err}
        end
    end

    local key = "/" .. uri_segs[4]
    -- core.log.info("key: ", key)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(uri_segs)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 400, {error_msg = "missing route id"}
    end

    local key = "/" .. resource .. "/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
