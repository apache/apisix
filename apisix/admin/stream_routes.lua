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
local utils = require("apisix.admin.utils")
local config_util = require("apisix.core.config_util")
local routes = require("apisix.stream.router.ip_port").routes
local stream_route_checker = require("apisix.stream.router.ip_port").stream_route_checker
local tostring = tostring


local _M = {
    version = 0.1,
    need_v3_filter = true,
}

local function check_router_refer(items, id)
    local refer_list = {}
    local referkey = "/stream_routes_refer/".. id
    local _, err = core.etcd.delete(referkey)
    core.log.warn(err)
    for _, item in config_util.iterate_values(items) do
        if item.value == nil then
            goto CONTINUE
        end
        local  r_id = string.gsub(item["key"],"/","_")
        local route = item.value
        if route.protocol and route.protocol.superior_id then
	        local data
            local setkey="/stream_routes_refer/"..route.protocol.superior_id
            local res, err = core.etcd.get(setkey,false)
            if res then
	            if res.body.node == nil then
                    data = core.json.decode("{}")
	                data[r_id]=1
                else
                    data = res.body.node.value
	                data[r_id]=1
                end
            end 
            local setres, err = core.etcd.set(setkey, data)
            if not setres then
                core.log.error("failed to put stream route[", setkey, "]: ", err)
            end
        end
        ::CONTINUE::
     end
     local rescheck, _ = core.etcd.get(referkey,not id) 
     if rescheck then
         if rescheck.body.node  ~= nil then
             if type(rescheck.body.node.value) == "table" then
                 for v,_ in pairs(rescheck.body.node.value) do
	             table.insert(refer_list,v)
                 end
             end
         end
     end
     return refer_list
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

    local items,_ = routes()
    local key = "/stream_routes/" .. id
    -- core.log.info("key: ", key)
    local refer_list=check_router_refer(items,id)
    local warn_message
    if #refer_list >0 then
        warn_message = key.." is refered by "..table.concat(refer_list,";;")
    else 
        warn_message = key.." is refered by None"
    end

    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete stream route[", key, "]: ", err)
        return 503, {error_msg = err}
    end
    res.body["refer"]=warn_message
    return res.status, res.body
end


return _M
