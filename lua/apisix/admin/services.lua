local core = require("apisix.core")
local routes = require("apisix.http.route").routes
local schema_plugin = require("apisix.admin.plugins").check_schema
local tostring = tostring
local ipairs = ipairs
local tonumber = tonumber


local _M = {
    version = 0.1,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing service id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong service id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong service id"}
    end


    core.log.info("schema: ", core.json.delay_encode(core.schema.service))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.service, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if need_id and not tonumber(id) then
        return nil, {error_msg = "wrong type of service id"}
    end

    local upstream_id = conf.upstream_id
    if upstream_id then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
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


function _M.get(id)
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


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/services"
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    -- todo: need to check if any route is still using this service now.
    if not id then
        return 400, {error_msg = "missing service id"}
    end

    local routes, routes_ver = routes()
    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if route.value and route.value.service_id
               and tostring(route.value.service_id) == id then
                return 400, {error_msg = "can not delete this service directly,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local key = "/services/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
