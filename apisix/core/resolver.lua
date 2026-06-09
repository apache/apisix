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

--- Domain Resolver.
--
-- @module core.resolver

local json           = require("apisix.core.json")
local log            = require("apisix.core.log")
local utils          = require("apisix.core.utils")
local dns_client     = require("apisix.core.dns.client")
local dns_utils      = require("resty.dns.utils")
local config_local   = require("apisix.core.config_local")
local ipairs         = ipairs
local table_sort     = table.sort


local HOSTS_IP_MATCH_CACHE = {}


local _M = {}


local function init_hosts_ip()
    local hosts, err = dns_utils.parseHosts()
    if not hosts then
        return hosts, err
    end
    HOSTS_IP_MATCH_CACHE = hosts
end


function _M.init_resolver(args)
    --  initialize /etc/hosts
    init_hosts_ip()

    local dns_resolver = args and args["dns_resolver"]
    utils.set_resolver(dns_resolver)
    log.info("dns resolver ", json.delay_encode(dns_resolver, true))
end

---
--  Resolve domain name to ip.
--
-- @function core.resolver.parse_domain
-- @tparam string host Domain name that need to be resolved.
-- @treturn string The IP of the domain name after being resolved.
-- @usage
-- local ip, err = core.resolver.parse_domain("apache.org") -- "198.18.10.114"
function _M.parse_domain(host)
    local rev = HOSTS_IP_MATCH_CACHE[host]
    local enable_ipv6 = config_local.local_conf().apisix.enable_ipv6
    if rev then
        -- use ipv4 in high priority
        local ip = rev["ipv4"]
        if enable_ipv6 and not ip then
            ip = rev["ipv6"]
        end
        if ip then
            -- meet test case
            log.info("dns resolve ", host, ", result: ", json.delay_encode(ip))
            log.info("dns resolver domain: ", host, " to ", ip)
            return ip
        end
    end

    local ip_info, err = utils.dns_parse(host)
    if not ip_info then
        log.error("failed to parse domain: ", host, ", error: ",err)
        return nil, err
    end

    log.info("parse addr: ", json.delay_encode(ip_info))
    log.info("resolver: ", json.delay_encode(utils.get_resolver()))
    log.info("host: ", host)
    if ip_info.address then
        log.info("dns resolver domain: ", host, " to ", ip_info.address)
        return ip_info.address
    end

    return nil, "failed to parse domain"
end


local function sort_ip(a, b)
    return a < b
end


function _M.parse_domain_all(host)
    local ips = {}
    local seen = {}

    local rev = HOSTS_IP_MATCH_CACHE[host]
    local enable_ipv6 = config_local.local_conf().apisix.enable_ipv6
    if rev then
        if rev["ipv4"] then
            ips[#ips + 1] = rev["ipv4"]
            seen[rev["ipv4"]] = true
        end

        if enable_ipv6 and rev["ipv6"] and not seen[rev["ipv6"]] then
            ips[#ips + 1] = rev["ipv6"]
        end
    end

    if #ips > 0 then
        table_sort(ips, sort_ip)
        log.info("dns resolve ", host, ", result: ", json.delay_encode(ips))
        return ips
    end

    local records, err = utils.dns_parse(host, dns_client.RETURN_ALL)
    if not records then
        log.error("failed to parse domain: ", host, ", error: ", err)
        return nil, err
    end

    log.info("parse addr: ", json.delay_encode(records))
    log.info("resolver: ", json.delay_encode(utils.get_resolver()))
    log.info("host: ", host)

    for _, record in ipairs(records) do
        local ip = record.address
        if ip and not seen[ip] then
            ips[#ips + 1] = ip
            seen[ip] = true
        end
    end

    if #ips == 0 then
        return nil, "failed to parse domain"
    end

    table_sort(ips, sort_ip)
    log.info("dns resolve ", host, ", result: ", json.delay_encode(ips))
    return ips
end


return _M
