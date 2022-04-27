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
local ngx = ngx
local plugin_name = "syslog"

local batch_processor_manager = bp_manager_mod.new("stream sys logger")
local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        flush_limit = {type = "integer", minimum = 1, default = 4096},
        drop_limit = {type = "integer", default = 1048576},
        timeout = {type = "integer", minimum = 1, default = 3000},
        sock_type = {type = "string", default = "tcp", enum = {"tcp", "udp"}},
        pool_size = {type = "integer", minimum = 5, default = 5},
        tls = {type = "boolean", default = false}
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
    return core.schema.check(schema, conf)
end


-- log phase in APISIX
function _M.log(conf, ctx)
    local entry = log_util.get_full_log_in_stream(ngx)
    syslog.push_entry(conf, ctx, entry)
end


return _M