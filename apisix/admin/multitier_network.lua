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
local utils = require("apisix.admin.utils")


local _M = {
    version = 0.1,
}


local function check_conf(conf)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.multitier_network))
    core.log.info("conf  : ", core.json.delay_encode(conf))

    local ok, err = core.schema.check(core.schema.multitier_network, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return true
end


function _M.put(_, conf)
    local ok, err = check_conf(conf)
    if not ok then
        return 400, err
    end

    utils.inject_timestamp(conf)

    local key = "/multitier_network"
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put multitier network: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get()
    local key = "/multitier_network"
    local res, err = core.etcd.get(key, false)
    if not res then
        core.log.error("failed to get multitier network: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete()
    local key = "/multitier_network"
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete multitier network: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
