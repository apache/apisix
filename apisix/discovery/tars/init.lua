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
local process = require("ngx.process")

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

local endpoint_dict
local default_weight

local last_fetch_full_time = 0
local last_fetch_error

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local activated_buffer = core.table.new(10, 0)
local nodes_buffer = core.table.new(0, 5)

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
        core.log.error("set endpoint version into discovery DICT failed, ", err)
        return
    end
    _, err = endpoint_dict:safe_set(servant, endpoint_content)
    if err then
        core.log.error("set endpoint into discovery DICT failed, ", err)
        endpoint_dict:delete(servant .. "#version")
    end
end


local function delete_endpoint(servant)
    core.log.info("delete servant ", servant)
    endpoint_dict:delete(servant .. "#version")
    endpoint_dict:delete(servant)
end


local function create_endpoint_lrucache(servant)
    local endpoint_content = endpoint_dict:get_stale(servant)
    if not endpoint_content then
        core.log.error("get empty endpoint content from discovery DICT, servant: ", servant)
        return nil
    end

    local endpoint = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.error("decode endpoint content failed, content: ", endpoint_content)
        return nil
    end

    return endpoint
end


local function get_endpoint(servant)
    local endpoint_version = endpoint_dict:get_stale(servant .. "#version")
    if not endpoint_version then
        return nil
    end

    return endpoint_lrucache(servant, endpoint_version, create_endpoint_lrucache, servant)
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
                return err
            end
        end
        extract_endpoint(res)
    end
    endpoint_dict:flush_expired()
end


local function fetch_incremental(db_cli)
    local res, err, errcode, sqlstate = db_cli:query(incremental_query_sql)
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
                return err
            end
            return err
        end
        extract_endpoint(res)
    end
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

    if last_fetch_error or last_fetch_full_time + conf.full_fetch_interval <= now then
        last_fetch_full_time = now
        last_fetch_error = fetch_full(db_cli)
    else
        last_fetch_error = fetch_incremental(db_cli)
    end

    if not last_fetch_error then
        db_cli:set_keepalive(120 * 1000, 1)
    end
end


function _M.nodes(servant)
    return get_endpoint(servant)
end


function _M.init_worker()
    -- TODO: maybe we can read dict name from discovery config
    endpoint_dict = ngx.shared.discovery
    if not endpoint_dict then
        error("failed to get nginx shared dict: discovery, please check your APISIX version")
    end

    if process.type() ~= "privileged agent" then
        return
    end

    local conf = local_conf.discovery.tars
    default_weight = local_conf.discovery.tars.default_weight or 100

    core.log.info("conf ", core.json.encode(conf, true))
    local backtrack_time = conf.incremental_fetch_interval + 5
    incremental_query_sql = format(incremental_query_sql, backtrack_time, backtrack_time)

    ngx.timer.at(0, fetch_endpoint, conf)
    ngx.timer.every(conf.incremental_fetch_interval, fetch_endpoint, conf)
end


return _M
