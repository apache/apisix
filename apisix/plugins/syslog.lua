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
local logger_socket = require("resty.logger.socket")
local plugin_name = "syslog"
local ngx = ngx

local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        flush_limit = {type = "integer", minimum = 1, default = 4096},
        drop_limit = {type = "integer", default = 1048576},
        timeout = {type = "integer", minimum = 1, default = 3},
        sock_type = {type = "string", default = "tcp"},
        max_retry_times = {type = "integer", minimum = 1, default = 3},
        retry_interval = {type = "integer", minimum = 10, default = 100},
        pool_size = {type = "integer", minimum = 5, default = 5},
        tls = {type = "boolean", default = false},
    },
    required = {"host", "port"}
}

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local _M = {
    version = 0.1,
    priority = 401,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.flush_syslog(logger)
    local ok, err = logger:flush(logger)
    if not ok then
        core.log.error("failed to flush message:", err)
    end
end

-- log phase in APISIX
function _M.log(conf)
    local entry = log_util.get_full_log(ngx)

    if not entry.route_id then
        core.log.error("failed to obtain the route id for sys logger")
        return
    end

    -- fetch api_ctx
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx cannot proceed with sys logger plugin")
        return core.response.exit(500)
    end

    -- fetch it from lrucache
    local logger, err =  lrucache(api_ctx.conf_type .. "#" .. api_ctx.conf_id, api_ctx.conf_version,
        logger_socket.new, logger_socket, {
            host = conf.host,
            port = conf.port,
            flush_limit = conf.flush_limit,
            drop_limit = conf.drop_limit,
            timeout = conf.timeout,
            sock_type = conf.sock_type,
            max_retry_times = conf.max_retry_times,
            retry_interval = conf.retry_interval,
            pool_size = conf.pool_size,
            tls = conf.tls,
        })

    if not logger then
        core.log.error("failed when initiating the sys logger processor", err)
    end

    -- reuse the logger object
    local ok, err = logger:log(core.json.encode(entry))
    if not ok then
        core.log.error("failed to log message", err)
    end
end

return _M
