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
local require = require
local core = require("apisix.core")
local utils = require("apisix.admin.utils")
local iterate_values = require("apisix.core.config_util").iterate_values
local stream_route_checker = require("apisix.stream.router.ip_port").stream_route_checker
local tostring = tostring
local table = table
local filter = require("apisix.router").filter


local _M = {
    version = 0.1,
    need_v3_filter = true,
}

local function check_router_refer(items, id)
    local warn_message = nil
    local refer_list =  core.tablepool.fetch("refer_list", #items, 0)
    for _, item in iterate_values(items) do
        if item.value == nil then
            goto CONTINUE
        end
        local route = item.value
        if route.protocol and route.protocol.superior_id and route.protocol.superior_id == id then
            table.insert(refer_list, item["key"])
        end
        ::CONTINUE::
    end
    if #refer_list > 0  then
        warn_message = "/stream_routes/" .. id .. " is referred by "
                        .. table.concat(refer_list,",")
    end
    core.tablepool.release("refer_list", refer_list)
    return warn_message
end

local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing stream route id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong stream route id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong stream route id"}
    end

    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(core.schema.stream_route))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.stream_route, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
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

    local ok, err = stream_route_checker(conf, true)
    if not ok then
        return nil, {error_msg = err}
    end

    return need_id and id or true
end

function _M.stream_routes()
    core.config.init()
    local router_stream = require("apisix.stream.router.ip_port")
    router_stream.stream_init_worker(filter)
    _M.router_stream = router_stream
    return _M.router_stream.routes()
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/stream_routes/" .. id

    local ok, err = utils.inject_conf_with_prev_conf("stream_routes", key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put stream route[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/stream_routes"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get stream route[", key, "]: ", err)
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

    local key = "/stream_routes"
    utils.inject_timestamp(conf)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post stream route[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing stream route id"}
    end

    local items, _ = _M.stream_routes()
    if items ~= nil then
        local warn_message = check_router_refer(items, id)
        if warn_message ~= nil then
            return 400, warn_message
        end
    end

    local key = "/stream_routes/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete stream route[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


return _M
