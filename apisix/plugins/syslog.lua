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
local log_util = require("apisix.utils.log-util")
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local syslog = require("apisix.plugins.syslog.init")
local plugin_name = "syslog"
local ngx = ngx

local batch_processor_manager = bp_manager_mod.new("http sys logger")
local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        max_retry_times = {type = "integer", minimum = 1},
        retry_interval = {type = "integer", minimum = 0},
        flush_limit = {type = "integer", minimum = 1, default = 4096},
        drop_limit = {type = "integer", default = 1048576},
        timeout = {type = "integer", minimum = 1, default = 3000},
        sock_type = {type = "string", default = "tcp", enum = {"tcp", "udp"}},
        pool_size = {type = "integer", minimum = 5, default = 5},
        tls = {type = "boolean", default = false},
        include_req_body = {type = "boolean", default = false}
    },
    required = {"host", "port"}
}


local schema = batch_processor_manager:wrap_schema(schema)

local _M = {
    version = 0.1,
    priority = 401,
    name = plugin_name,
    schema = schema,
    flush_syslog = syslog.flush_syslog,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    conf.max_retry_count = conf.max_retry_times or conf.max_retry_count
    conf.retry_delay = conf.retry_interval or conf.retry_delay
    return true
end


function _M.log(conf, ctx)
    local entry = log_util.get_full_log(ngx, conf)
    syslog.push_entry(conf, ctx, entry)
end


return _M
