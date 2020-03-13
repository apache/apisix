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
local http = require("resty.http")
local cjson = require('cjson')
local ngx = ngx
local ipairs = ipairs

local register = require("skywalking.register")

local _M = {}

local function register_service(conf)
    local endpoint = conf.endpoint

    local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
    local service_id = tracing_buffer:get(endpoint .. '_service_id')
    if service_id then
        return service_id
    end

    local service_name = conf.service_name
    local service = register.newServiceRegister(service_name)

    local httpc = http.new()
    local res, err = httpc:request_uri(endpoint .. '/v2/service/register',
                        {
                            method = "POST",
                            body = core.json.encode(service),
                            headers = {
                                ["Content-Type"] = "application/json",
                            },
                        })
    if not res then
        core.log.error("skywalking service register failed, request uri: ",
                       endpoint .. '/v2/service/register', ", err: ", err)

    elseif res.status == 200 then
        core.log.debug("skywalking service register response: ", res.body)
        local register_results = cjson.decode(res.body)

        for _, result in ipairs(register_results) do
            if result.key == service_name then
                service_id = result.value
                core.log.debug("skywalking service registered, service id:"
                                .. service_id)
            end
        end

    else
        core.log.error("skywalking service register failed, request uri:",
                        endpoint .. "/v2/service/register",
                        ", response code:", res.status)
    end

    if service_id then
        tracing_buffer:set(endpoint .. '_service_id', service_id)
    end

    return service_id
end

local function register_service_instance(conf, service_id)
    local endpoint = conf.endpoint

    local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
    local instance_id = tracing_buffer:get(endpoint .. '_instance_id')
    if instance_id then
        return instance_id
    end

    local service_instance_name = core.id.get()
    local service_instance = register.newServiceInstanceRegister(
                                        service_id,
                                        service_instance_name,
                                        ngx.now() * 1000)

    local httpc = http.new()
    local res, err = httpc:request_uri(endpoint .. '/v2/instance/register',
                        {
                            method = "POST",
                            body = core.json.encode(service_instance),
                            headers = {
                                ["Content-Type"] = "application/json",
                            },
                        })

    if not res then
        core.log.error("skywalking service Instance register failed",
                        ", request uri: ", conf.endpoint .. '/v2/instance/register',
                        ", err: ", err)

    elseif res.status == 200 then
        core.log.debug("skywalking service instance register response: ", res.body)
        local register_results = cjson.decode(res.body)

        for _, result in ipairs(register_results) do
            if result.key == service_instance_name then
                instance_id = result.value
                core.log.debug("skywalking service Instance registered, ",
                                "service instance id: ", instance_id)
            end
        end

    else
        core.log.error("skywalking service instance register failed, ",
                        "response code:", res.status)
    end

    if instance_id then
        tracing_buffer:set(endpoint .. '_instance_id', instance_id)
    end

    return instance_id
end

local function ping(endpoint)
    local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
    local ping_pkg = register.newServiceInstancePingPkg(
        tracing_buffer:get(endpoint .. '_instance_id'),
        core.id.get(),
        ngx.now() * 1000)

    local httpc = http.new()
    local _, err = httpc:request_uri(endpoint .. '/v2/instance/heartbeat', {
        method = "POST",
        body = core.json.encode(ping_pkg),
        headers = {
            ["Content-Type"] = "application/json",
        },
    })

    if err then
        core.log.error("skywalking agent ping failed, err: ", err)
    end
end

-- report trace segments to the backend
local function report_traces(endpoint)
    local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
    local segment = tracing_buffer:rpop(endpoint .. '_segment')

    local count = 0

    local httpc = http.new()

    while segment ~= nil do
        local res, err = httpc:request_uri(endpoint .. '/v2/segments', {
            method = "POST",
            body = segment,
            headers = {
                ["Content-Type"] = "application/json",
            },
        })

        if err == nil then
            if res.status ~= 200 then
                core.log.error("skywalking segment report failed, response code ", res.status)
                break
            else
                count = count + 1
            end
        else
            core.log.error("skywalking segment report failed, err: ", err)
            break
        end

        segment = tracing_buffer:rpop('segment')
    end

    if count > 0 then
        core.log.debug(count, " skywalking segments reported")
    end
end

do
    local heartbeat_timer

function _M.heartbeat(conf)
    local sw_heartbeat = function()
        local service_id = register_service(conf)
        if not service_id then
            return
        end

        local service_instance_id = register_service_instance(conf, service_id)
        if not service_instance_id then
            return
        end

        report_traces(conf.endpoint)
        ping(conf.endpoint)
    end

    local err
    if ngx.worker.id() == 0 and not heartbeat_timer then
        heartbeat_timer, err = core.timer.new("skywalking_heartbeat",
                                            sw_heartbeat,
                                            {check_interval = 3}
                                            )
        if not heartbeat_timer then
            core.log.error("failed to create skywalking_heartbeat timer: ", err)
        else
            core.log.info("succeed to create timer: skywalking heartbeat")
        end
    end
end

end -- do


return _M
