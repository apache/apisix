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
local schema_plugin = require("apisix.admin.plugins").check_schema
local v3_adapter = require("apisix.admin.v3_adapter")
local tostring = tostring


local _M = {
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong id"}
    end

    conf.id = id

    core.log.info("conf: ", core.json.delay_encode(conf))

    local ok, err = schema_plugin(conf.plugins)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


function _M.put(id, conf)
    local ok, err = check_conf(id, conf, true)
    if not ok then
        return 400, err
    end

    local key = "/consumer_groups/" .. id

    local ok, err = utils.inject_conf_with_prev_conf("consumer_group", key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put consumer group[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/consumer_groups"
    if id then
        key = key .. "/" .. id
    end
    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get consumer group[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    v3_adapter.filter(res.body)
    return res.status, res.body
end


return _M
