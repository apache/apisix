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

local require            = require
local local_conf         = require("apisix.core.config_local").local_conf()
local core               = require("apisix.core")
local cjson              = require('cjson')
local http               = require('resty.http')
local log                = core.log
local ipairs             = ipairs
local math               = math
local random             = math.random
local consul_conf        = local_conf.discovery.consul


local function get_consul_server_endpoint(service_name)
    local server = consul_conf.servers[random(1, #consul_conf.servers)]
    if string.sub(server,#server) == "/" then
        server = string.sub(server, 1, #server - 1)
    end
    
    local path = "/v1/catalog/service/" .. service_name

    local split = "?"

    if consul_conf.dc ~= nil and consul_conf.dc ~= "" then
        path = path .. split .. "dc=" .. consul_conf.dc
        if split == "?" then
            split = "&"
        end
    end

    if consul_conf.alc_token ~= nil and #consul_conf.alc_token ~= "" then
        path = path .. split .. "token=" .. consul_conf.alc_token
        if split == "?" then
            split = "&"
        end
    end

    local endpoint = server .. path
    
    return endpoint
end


local function get_nodes(service_name)
    local endpoint = get_consul_server_endpoint(service_name)

    local http_client = http.new()

    local response, error = http_client:request_uri(endpoint, {
        method = "GET"
    })

    if not response then
        log.error("request error: ", error)
        return
    end

    local json_convert = cjson.new()
    local response_body = json_convert.decode(response.body)

    if not response_body or #response_body == 0 then
        log.error("cannot get service ["..service_name.."] nodes, please check the service status in consul")
        return
    end

    local nodes = {}

    for index, node in ipairs(response_body) do
        nodes[index] = {
            host = node.ServiceAddress,
            port = node.ServicePort,
            weight = 100,
            metadata = {
                management = {
                    port = node.ServicePort
                }
            }
        }
    end

    return nodes
end

local _M = {
    -- version = 0.1,
}

function _M.nodes(service_name)
    local nodes = get_nodes(service_name)
    return nodes
end

function _M.init_worker()
    -- local ok, err = core.schema.check(schema, consul_conf)
    -- if not ok then
    --     log.error("invalid config" .. err)
    --     return
    -- end
end


return _M
