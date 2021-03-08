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
local config_local = require("apisix.core.config_local")
local ipairs = ipairs
local error = error


local dns_client
local schema = {
    type = "object",
    properties = {
        servers = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
            },
        },
    },
    required = {"servers"}
}


local _M = {}


function _M.nodes(service_name)
    local host, port = core.utils.parse_addr(service_name)
    core.log.info("discovery dns with host ", host, ", port ", port)

    local records, err = dns_client:resolve(host, core.dns_client.RETURN_ALL)
    if not records then
        return nil, err
    end

    local nodes = core.table.new(#records, 0)
    for i, r in ipairs(records) do
        if r.address then
            nodes[i] = {host = r.address, weight = r.weight or 1, port = r.port or port}
        end
    end

    return nodes
end


function _M.init_worker()
    local local_conf = config_local.local_conf()
    local ok, err = core.schema.check(schema, local_conf.discovery.dns)
    if not ok then
        error("invalid dns discovery configuration: " .. err)
        return
    end

    local servers = core.table.try_read_attr(local_conf, "discovery", "dns", "servers")

    local opts = {
        hosts = {},
        resolvConf = {},
        nameservers = servers,
        order = {"last", "A", "AAAA", "SRV", "CNAME"},
    }

    local client, err = core.dns_client.new(opts)
    if not client then
        error("failed to init the dns client: ", err)
        return
    end

    dns_client = client
end


return _M
