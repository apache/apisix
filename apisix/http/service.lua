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
local core   = require("apisix.core")
local apisix_upstream = require("apisix.upstream")
local plugin_checker = require("apisix.plugin").plugin_checker
local services
local error = error


local _M = {
    version = 0.2,
}


function _M.get(service_id)
    return services:get(service_id)
end


function _M.services()
    if not services then
        return nil, nil
    end

    return services.values, services.conf_version
end


local function filter(service)
    service.has_domain = false
    if not service.value then
        return
    end

    apisix_upstream.filter_upstream(service.value.upstream, service)

    core.log.info("filter service: ", core.json.delay_encode(service, true))
end


function _M.init_worker()
    local err
    services, err = core.config.new("/services", {
        automatic = true,
        item_schema = core.schema.service,
        checker = plugin_checker,
        filter = filter,
    })
    if not services then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
