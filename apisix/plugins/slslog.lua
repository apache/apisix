local core = require("apisix.core")
local log_util = require("apisix.utils.log-util")
local batch_processor = require("apisix.utils.batch-processor")
local logger_socket = require("resty.logger.socket")
local plugin_name = "slslog"
local ngx = ngx
local buffers = {}
local ipairs   = ipairs
local stale_timer_running = false;
local timer_at = ngx.timer.at
local tostring = tostring


local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        name = {type = "string", default = "sys logger"},
        flush_limit = {type = "integer", minimum = 1, default = 4096},
        drop_limit = {type = "integer", default = 1048576},
        timeout = {type = "integer", minimum = 1, default = 3},
        sock_type = {type = "string", default = "tcp"},
        max_retry_times = {type = "integer", minimum = 1, default = 1},
        retry_interval = {type = "integer", minimum = 0, default = 1},
        pool_size = {type = "integer", minimum = 5, default = 5},
        tls = {type = "boolean", default = false},
        batch_max_size = {type = "integer", minimum = 1, default = 1000},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        include_req_body = {type = "boolean", default = false}
    },
    required = {"host", "port"}
}

local _M = {
    version = 0.1,
    priority = 401,
    name = plugin_name,
    schema = schema,
}

return _M