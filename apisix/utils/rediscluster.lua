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
local rediscluster      = require("resty.rediscluster")
local core              = require("apisix.core")
local ipairs            = ipairs

local _M = {version = 0.1}

local function new_redis_cluster(conf, dict_name)
    local config = {
        name = conf.redis_cluster_name,
        serv_list = {},
        read_timeout = conf.redis_timeout,
        auth = conf.redis_password,
        dict_name = dict_name,
        connect_opts = {
            ssl = conf.redis_cluster_ssl,
            ssl_verify = conf.redis_cluster_ssl_verify,
        }
    }

    for i, conf_item in ipairs(conf.redis_cluster_nodes) do
        local host, port, err = core.utils.parse_addr(conf_item)
        if err then
            return nil, "failed to parse address: " .. conf_item
                        .. " err: " .. err
        end

        config.serv_list[i] = {ip = host, port = port}
    end

    local red_cli, err = rediscluster:new(config)
    if not red_cli then
        return nil, "failed to new redis cluster: " .. err
    end

    return red_cli
end


function _M.new(conf, dict_name)
     return new_redis_cluster(conf, dict_name)
end


return _M
