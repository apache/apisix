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
local ngx = ngx
local format = string.format
local ipairs = ipairs
local error = error
local tonumber = tonumber
local local_conf = require("apisix.core.config_local").local_conf()
local core = require("apisix.core")
local mysql = require("resty.mysql")
local is_http = ngx.config.subsystem == "http"
local support_process, process = pcall(require, "ngx.process")

local endpoint_dict

local full_query_sql = [[ select servant, group_concat(endpoint order by endpoint) as endpoints
from t_server_conf left join t_adapter_conf tac using (application, server_name, node_name)
where setting_state = 'active' and present_state = 'active'
group by servant ]]

local incremental_query_sql = [[
select servant, (setting_state = 'active' and present_state = 'active') activated,
group_concat(endpoint order by endpoint) endpoints
from t_server_conf left join t_adapter_conf tac using (application, server_name, node_name)
where (application, server_name) in
(
select application, server_name from t_server_conf
where registry_timestamp > now() - interval %d second
union
select application, server_name from t_adapter_conf
where registry_timestamp > now() - interval %d second
)
group by servant, activated order by activated desc ]]

local _M = {
    version = 0.1,
}

local default_weight

local last_fetch_full_time = 0
local last_db_error

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local activated_buffer = core.table.new(10, 0)
local nodes_buffer = core.table.new(0, 5)


--[[
endpoints format as follows:
  tcp -h 172.16.1.1 -p 11 -t 6000 -e 0,tcp -e 0 -p 12 -h 172.16.1.1,tcp -p 13 -h 172.16.1.1
we extract host and port value via endpoints_pattern
--]]
local endpoints_pattern = core.table.concat(
        { [[tcp(\s*-[te]\s*(\S+)){0,2}\s*-([hpHP])\s*(\S+)(\s*-[teTE]\s*(\S+))]],
          [[{0,2}\s*-([hpHP])\s*(\S+)(\s*-[teTE]\s*(\S+)){0,2}\s*(,|$)]] }
)


local function update_endpoint(servant, nodes)
    local endpoint_content = core.json.encode(nodes, true)
    local endpoint_version = ngx.crc32_long(endpoint_content)
    core.log.debug("set servant ", servant, endpoint_content)
    local _, err
    _, err = endpoint_dict:safe_set(servant .. "#version", endpoint_version)
    if err then
        core.log.error("set endpoint version into nginx shared dict failed, ", err)
        return
    end
    _, err = endpoint_dict:safe_set(servant, endpoint_content)
    if err then
        core.log.error("set endpoint into nginx shared dict failed, ", err)
        endpoint_dict:delete(servant .. "#version")
    end
end


local function delete_endpoint(servant)
    core.log.info("delete servant ", servant)
    endpoint_dict:delete(servant .. "#version")
    endpoint_dict:delete(servant)
end


local function add_endpoint_to_lrucache(servant)
    local endpoint_content, err = endpoint_dict:get_stale(servant)
    if not endpoint_content then
        core.log.error("get empty endpoint content, servant: ", servant, ", err: ", err)
        return nil
    end

    local endpoint, err = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.error("decode json failed, content: ", endpoint_content, ", err: ", err)
        return nil
    end

    return endpoint
end


local function get_endpoint(servant)

    --[[
    fetch_full function will:
         1: call endpoint_dict:flush_all()
         2: setup servant:nodes pairs into endpoint_dict
         3: call endpoint_dict:flush_expired()

    get_endpoint may be called during the 2 step of the fetch_full function,
    so we must use endpoint_dict:get_stale() to get value instead endpoint_dict:get()
    --]]

    local endpoint_version, err = endpoint_dict:get_stale(servant .. "#version")
    if not endpoint_version  then
        if err then
            core.log.error("get empty endpoint version, servant: ", servant, ", err: ", err)
        end
        return nil
    end
    return endpoint_lrucache(servant, endpoint_version, add_endpoint_to_lrucache, servant)
end


local function extract_endpoint(query_result)
    for _, p in ipairs(query_result) do
        repeat
            local servant = p.servant

            if servant == ngx.null then
                break
            end

            if p.activated == 1 then
                activated_buffer[servant] = ngx.null
            elseif p.activated == 0 then
                if activated_buffer[servant] == nil then
                    delete_endpoint(servant)
                end
                break
            end

            core.table.clear(nodes_buffer)
            local iterator = ngx.re.gmatch(p.endpoints, endpoints_pattern, "jao")
            while true do
                local captures, err = iterator()
                if err then
                    core.log.error("gmatch failed, error: ", err, " , endpoints: ", p.endpoints)
                    break
                end

                if not captures then
                    break
                end

                local host, port
                if captures[3] == "h" or captures[3] == "H" then
                    host = captures[4]
                    port = tonumber(captures[8])
                else
                    host = captures[8]
                    port = tonumber(captures[4])
                end

                core.table.insert(nodes_buffer, {
                    host = host,
                    port = port,
                    weight = default_weight,
                })
            end
            update_endpoint(servant, nodes_buffer)
        until true
    end
end


local function fetch_full(db_cli)
    local res, err, errcode, sqlstate = db_cli:query(full_query_sql)
    --[[
    res format is as follows:
    {
        {
            servant = "A.AServer.FirstObj",
            endpoints = "tcp -h 172.16.1.1 -p 10001 -e 0 -t 3000,tcp -p 10002 -h 172.16.1.2 -t 3000"
        },
        {
            servant = "A.AServer.SecondObj",
            endpoints = "tcp -t 3000 -p 10002 -h 172.16.1.2"
        },
    }

    if current endpoint_dict is as follows:
      key1:nodes1, key2:nodes2, key3:nodes3

    then fetch_full get follow results:
      key1:nodes1, key4:nodes4, key5:nodes5

    at this time, we need
      1: setup key4:nodes4, key5:nodes5
      2: delete key2:nodes2, key3:nodes3

    to achieve goals, we should:
      1: before setup results, execute endpoint_dict:flush_all()
      2:  after setup results, execute endpoint_dict:flush_expired()
    --]]
    if not res then
        core.log.error("query failed, error: ", err, ", ", errcode, " ", sqlstate)
        return err
    end

    endpoint_dict:flush_all()
    extract_endpoint(res)

    while err == "again" do
        res, err, errcode, sqlstate = db_cli:read_result()
        if not res then
            if err then
                core.log.error("read result failed, error: ", err, ", ", errcode, " ", sqlstate)
            end
            return err
        end
        extract_endpoint(res)
    end
    endpoint_dict:flush_expired()

    return nil
end


local function fetch_incremental(db_cli)
    local res, err, errcode, sqlstate = db_cli:query(incremental_query_sql)
    --[[
    res is as follows:
    {
        {
            activated=1,
            servant = "A.AServer.FirstObj",
            endpoints = "tcp -h 172.16.1.1 -p 10001 -e 0 -t 3000,tcp -p 10002 -h 172.16.1.2 -t 3000"
        },
        {
            activated=0,
            servant = "A.AServer.FirstObj",
            endpoints = "tcp -t 3000 -p 10001 -h 172.16.1.3"
        },
        {
            activated=0,
            servant = "B.BServer.FirstObj",
            endpoints = "tcp -t 3000 -p 10002 -h 172.16.1.2"
        },
    }

    for each item:
      if activated==1, setup
      if activated==0, if there is a other item had same servant and activate==1, ignore
      if activated==0, and there is no other item had same servant, delete
    --]]
    if not res then
        core.log.error("query failed, error: ", err, ", ", errcode, " ", sqlstate)
        return err
    end

    core.table.clear(activated_buffer)
    extract_endpoint(res)

    while err == "again" do
        res, err, errcode, sqlstate = db_cli:read_result()
        if not res then
            if err then
                core.log.error("read result failed, error: ", err, ", ", errcode, " ", sqlstate)
            end
            return err
        end
        extract_endpoint(res)
    end

    return nil
end


local function fetch_endpoint(premature, conf)
    if premature then
        return
    end

    local db_cli, err = mysql:new()
    if not db_cli then
        core.log.error("failed to instantiate mysql: ", err)
        return
    end
    db_cli:set_timeout(3000)

    local ok, err, errcode, sqlstate = db_cli:connect(conf.db_conf)
    if not ok then
        core.log.error("failed to connect mysql: ", err, ", ", errcode, ", ", sqlstate)
        return
    end

    local now = ngx.time()

    if last_db_error or last_fetch_full_time + conf.full_fetch_interval <= now then
        last_fetch_full_time = now
        last_db_error = fetch_full(db_cli)
    else
        last_db_error = fetch_incremental(db_cli)
    end

    if not last_db_error then
        db_cli:set_keepalive(120 * 1000, 1)
    end
end


function _M.nodes(servant)
    return get_endpoint(servant)
end

local function get_endpoint_dict()
    local shm = "tars"

    if not is_http then
        shm = shm .. "-stream"
    end

    return ngx.shared[shm]
end

function _M.init_worker()
    if not support_process then
        core.log.error("tars discovery not support in subsystem: ", ngx.config.subsystem,
                       ", please check if your openresty version >= 1.19.9.1 or not")
        return
    end

    endpoint_dict = get_endpoint_dict()
    if not endpoint_dict then
        error("failed to get lua_shared_dict: tars, please check your APISIX version")
    end

    if process.type() ~= "privileged agent" then
        return
    end

    local conf = local_conf.discovery.tars
    default_weight = conf.default_weight

    core.log.info("conf ", core.json.delay_encode(conf))
    local backtrack_time = conf.incremental_fetch_interval + 5
    incremental_query_sql = format(incremental_query_sql, backtrack_time, backtrack_time)

    ngx.timer.at(0, fetch_endpoint, conf)
    ngx.timer.every(conf.incremental_fetch_interval, fetch_endpoint, conf)
end


return _M
