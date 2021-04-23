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
local json = require("apisix.core.json")
local log = require("apisix.core.log")
local utils = require("apisix.core.utils")


local _M = {}


function _M.init_resolver(args)
    local dns_resolver = args and args["dns_resolver"]
    utils.set_resolver(dns_resolver)
    log.info("dns resolver ", json.delay_encode(dns_resolver, true))
end


function _M.parse_domain(host)
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


return _M
