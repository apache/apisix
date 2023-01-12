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

local core          = require("apisix.core")
local config_local  = require("apisix.core.config_local")
local is_http       = ngx.config.subsystem == "http"
local ipairs        = ipairs
local error         = error


local dns_client
local _M = {}


function _M.nodes(service_name)
    local host, port = core.utils.parse_addr(service_name)
    core.log.info("discovery dns with host ", host, ", port ", port)

    local records, err = dns_client:resolve(host, core.dns_client.RETURN_ALL)
    if not records then
        return nil, err
    end

    local nodes = core.table.new(#records, 0)
    local index = 1
    for _, r in ipairs(records) do
        if r.address then
            local node_port = port
            if not node_port and r.port ~= 0 then
                -- if the port is zero, fallback to use the default
                node_port = r.port
            end

            -- ignore zero port when subsystem is stream
            if node_port or is_http then
                nodes[index] = {host = r.address, weight = r.weight or 1, port = node_port}
                if r.priority then
                    -- for SRV record, nodes with lower priority are chosen first
                    nodes[index].priority = -r.priority
                end
                index = index + 1
            end
        end
    end

    return nodes
end


function _M.init_worker()
    local local_conf = config_local.local_conf()
    local servers = local_conf.discovery.dns.servers

    local default_order = {"last", "SRV", "A", "AAAA", "CNAME"}
    local order = core.table.try_read_attr(local_conf, "discovery", "dns", "order")
    order = order or default_order

    local opts = {
        hosts = {},
        resolvConf = {},
        nameservers = servers,
        order = order,
    }

    local client, err = core.dns_client.new(opts)
    if not client then
        error("failed to init the dns client: ", err)
        return
    end

    dns_client = client
end


return _M
