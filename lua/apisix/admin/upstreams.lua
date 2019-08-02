local core = require("apisix.core")
local get_routes = require("apisix.http.route").routes
local get_services = require("apisix.http.service").services
local tostring = tostring
local ipairs = ipairs
local tonumber = tonumber
local type = type


local _M = {
    version = 0.1,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

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

    if need_id and not tonumber(id) then
        return nil, {error_msg = "wrong type of service id"}
    end


    if conf.type == "chash" and not conf.key then
        return nil, {error_msg = "missing key"}
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
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


function _M.get(id)
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


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
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


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing upstream id"}
    end

    local routes, routes_ver = get_routes()
    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.upstream_id
               and tostring(route.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local services, services_ver = get_services()
    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)
    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value
               and service.value.upstream_id
               and tostring(service.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " service [" .. service.value.id
                                         .. "] is still using it now"}
            end
        end
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
