--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local apisix_upstream = require("apisix.upstream")
local utils = require("apisix.admin.utils")
local tostring = tostring
local ipairs = ipairs
local type = type


local _M = {
    version = 0.2,
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

    -- let schema check id
    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(core.schema.upstream))
    core.log.info("conf: ", core.json.delay_encode(conf))

    local ok, err = apisix_upstream.check_upstream_conf(conf)
    if not ok then
        return nil, {error_msg = err}
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

    local ok, err = utils.inject_conf_with_prev_conf("upstream", key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put upstream[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/upstreams"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get upstream[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/upstreams"
    utils.inject_timestamp(conf)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post upstream[", key, "]: ", err)
        return 503, {error_msg = err}
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
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(id, conf, sub_path)
    if not id then
        return 400, {error_msg = "missing upstream id"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/upstreams" .. "/" .. id
    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get upstream [", key, "]: ", err)
        return 503, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
                  core.json.delay_encode(res_old, true))

    local new_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    if sub_path and sub_path ~= "" then
        local code, err, node_val = core.table.patch(new_value, sub_path, conf)
        new_value = node_val
        if code then
            return code, err
        end
        utils.inject_timestamp(new_value, nil, true)
    else
        new_value = core.table.merge(new_value, conf);
        utils.inject_timestamp(new_value, nil, conf)
    end

    core.log.info("new value ", core.json.delay_encode(new_value, true))

    local id, err = check_conf(id, new_value, true)
    if not id then
        return 400, err
    end

    local res, err = core.etcd.atomic_set(key, new_value, nil, modified_index)
    if not res then
        core.log.error("failed to set new upstream[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


return _M
