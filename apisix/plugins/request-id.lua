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
local bit = require("bit")
local core = require("apisix.core")
local snowflake = require("snowflake")
local uuid = require("resty.jit-uuid")
local process = require("ngx.process")
local timers = require("apisix.timers")
local tostring = tostring
local math_pow = math.pow

local plugin_name = "request-id"

local worker_number = nil
local snowflake_inited = nil

local attr = nil

local schema = {
    type = "object",
    properties = {
        header_name = {type = "string", default = "X-Request-Id"},
        include_in_response = {type = "boolean", default = true},
        algorithm = {type = "string", enum = {"uuid", "snowflake"}, default = "uuid"}
    }
}

local attr_schema = {
    type = "object",
    properties = {
        snowflake = {
            type = "object",
            properties = {
                enable = {type = "boolean"},
                snowflake_epoc = {type = "integer", minimum = 1, default = 1609459200000},
                node_id_bits = {type = "integer", minimum = 1, default = 5},
                sequence_bits = {type = "integer", minimum = 1, default = 10},
                datacenter_id_bits = {type = "integer", minimum = 1, default = 5},
                worker_number_ttl = {type = "integer", minimum = 1, default = 30},
                worker_number_interval = {type = "integer", minimum = 1, default = 10}
            }
        }
    }
}

local _M = {
    version = 0.1,
    priority = 11010,
    name = plugin_name,
    schema = schema
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Generates the current process worker number
local function gen_worker_number(max_number)
    if worker_number == nil then
        local etcd_cli, prefix = core.etcd.new()
        local prefix = prefix .. "/plugins/request-id/snowflake/"
        local uuid = uuid.generate_v4()
        local id = 1
        while (id <= max_number) do
            ::continue::
            local res, _ = etcd_cli:grant(attr.snowflake.worker_number_ttl)
            local _, err1 = etcd_cli:setnx(prefix .. tostring(id), uuid)
            local res2, err2 = etcd_cli:get(prefix .. tostring(id))

            if err1 or err2 or res2.body.kvs[1].value ~= uuid then
                core.log.notice("worker_number " .. id .. " is not available")
                id = id + 1
            else
                worker_number = id

                local _, err3 =
                    etcd_cli:set(
                    prefix .. tostring(id),
                    uuid,
                    {
                        prev_kv = true,
                        lease = res.body.ID
                    }
                )

                if err3 then
                    id = id + 1
                    etcd_cli:delete(prefix .. tostring(id))
                    core.log.error("set worker_number " .. id .. " lease error: " .. err3)
                    goto continue
                end

                local lease_id = res.body.ID
                local start_at = ngx.time()
                local handler = function()
                    local now = ngx.time()
                    if now - start_at < attr.snowflake.worker_number_interval then
                        return
                    end

                    local _, err4 = etcd_cli:keepalive(lease_id)
                    if err4 then
                        snowflake_inited = nil
                        worker_number = nil
                        core.log.error("snowflake worker_number: " .. id .." lease faild.")
                    end
                    start_at = now
                    core.log.info("snowflake worker_number: " .. id .." lease success.")
                end

                timers.register_timer("plugin#request-id", handler)
                core.log.info(
                    "timer created to lease snowflake algorithm worker number, interval: ",
                    attr.snowflake.worker_number_interval)
                core.log.notice("lease snowflake worker_number: " .. id)
                break
            end
        end

        if worker_number == nil then
            core.log.error("No worker_number is not available")
            return nil
        end
    end
    return worker_number
end


-- Split 'Worker Number' into 'Worker ID' and 'datacenter ID'
local function split_worker_number(worker_number, node_id_bits, datacenter_id_bits)
    local num = bit.tobit(worker_number)
    local worker_id = bit.band(num, math_pow(2, node_id_bits) - 1) + 1
    num = bit.rshift(num, node_id_bits)
    local datacenter_id = bit.band(num, math_pow(2, datacenter_id_bits) - 1) + 1
    return worker_id, datacenter_id
end


-- Initialize the snowflake algorithm
local function snowflake_init()
    if snowflake_inited == nil then
        local max_number = math_pow(2, (attr.snowflake.node_id_bits +
            attr.snowflake.datacenter_id_bits))
        worker_number = gen_worker_number(max_number)
        if worker_number == nil then
            return ""
        end
        local worker_id, datacenter_id = split_worker_number(worker_number,
            attr.snowflake.node_id_bits, attr.snowflake.datacenter_id_bits)
        core.log.notice("snowflake init datacenter_id: " ..
            datacenter_id .. " worker_id: " .. worker_id)
        snowflake.init(
            worker_id,
            datacenter_id,
            attr.snowflake.snowflake_epoc,
            attr.snowflake.node_id_bits,
            attr.snowflake.datacenter_id_bits,
            attr.snowflake.sequence_bits
        )
        snowflake_inited = true
    end
end


-- generate snowflake id
local function next_id()
    if snowflake_inited == nil then
        snowflake_init()
    end
    return snowflake:next_id()
end


local function get_request_id(algorithm)
    if algorithm == "uuid" then
        return uuid()
    end
    return next_id()
end


function _M.rewrite(conf, ctx)
    local headers = ngx.req.get_headers()
    local uuid_val = get_request_id(conf.algorithm)
    if not headers[conf.header_name] then
        core.request.set_header(ctx, conf.header_name, uuid_val)
    end

    if conf.include_in_response then
        ctx["request-id-" .. conf.header_name] = uuid_val
    end
end

function _M.header_filter(conf, ctx)
    if not conf.include_in_response then
        return
    end

    local headers = ngx.resp.get_headers()
    if not headers[conf.header_name] then
        core.response.set_header(conf.header_name, ctx["request-id-" .. conf.header_name])
    end
end

function _M.init()
    local local_conf = core.config.local_conf()
    attr = core.table.try_read_attr(local_conf, "plugin_attr", plugin_name)
    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("failed to check the plugin_attr[", plugin_name, "]", ": ", err)
        return
    end
    if attr.snowflake.enable then
        if process.type() == "worker" then
            ngx.timer.at(0, snowflake_init)
        end
    end
end


return _M
