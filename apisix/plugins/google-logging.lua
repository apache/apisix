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

local ngx = ngx
local tostring = tostring
local ipairs = ipairs
local sub_str = string.sub
local os_date = os.date

local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local ngx_update_time = ngx.update_time

local core = require("apisix.core")
local http = require("resty.http")
local log_util = require("apisix.utils.log-util")
local batch_processor = require("apisix.utils.batch-processor")
local google_oauth = require("apisix.plugins.google-logging.oauth")


local buffers = {}
local auth_config_cache
local stale_timer_running


local plugin_name = "google-logging"
local schema = {
    type = "object",
    properties = {
        auth_config = {
            type = "object",
            properties = {
                private_key = { type = "string" },
                project_id = { type = "string" },
                token_uri = { type = "string" },
                -- https://developers.google.com/identity/protocols/oauth2/scopes#logging
                scopes = {
                    type = "array",
                    items = {
                        description = "Google OAuth2 Authorization Scopes",
                        type = "string",
                    },
                    minItems = 1,
                    uniqueItems = true,
                    default = {
                        "https://www.googleapis.com/auth/logging.read",
                        "https://www.googleapis.com/auth/logging.write",
                        "https://www.googleapis.com/auth/logging.admin",
                        "https://www.googleapis.com/auth/cloud-platform"
                    }
                },
            },
            required = { "private_key", "project_id", "token_uri" }
        },
        auth_file = { type = "string" },
        -- https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource
        resource = {
            type = "object",
            properties = {
                type = { type = "string" },
                labels = { type = "object" }
            },
            default = {
                type = "global"
            },
            required = { "type" }
        },
        entries_uri = {
            type = "string",
            default = "https://logging.googleapis.com/v2/entries:write"
        },
        -- https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry
        log_id = { type = "string", default = "apisix.apache.org%2Flogs" },
        max_retry_count = { type = "integer", minimum = 0, default = 0 },
        retry_delay = { type = "integer", minimum = 0, default = 1 },
        buffer_duration = { type = "integer", minimum = 1, default = 60 },
        inactive_timeout = { type = "integer", minimum = 1, default = 10 },
        batch_max_size = { type = "integer", minimum = 1, default = 100 },
    },
    oneOf = {
        { required = { "auth_config" } },
        { required = { "auth_file" } },
    },
}


-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in ipairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, route id:", tostring(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end


local function send_to_google(oauth, entries)
    local http_new = http.new()
    local res, err = http_new:request_uri(oauth.entries_uri, {
        ssl_verify = false,
        method = "POST",
        body = core.json.encode({
            entries = entries,
            partialSuccess = false,
        }),
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. oauth:get_access_token(),
        },
    })

    if err then
        return nil, "failed to write log to google, ", err
    end

    if res.status ~= 200 then
        return nil, res.body
    end

    return res.body
end


local function get_auth_config(config)
    local err
    local auth_config = {}
    if config.auth_config then
        auth_config = config.auth_config
    end

    if config.auth_file then
        local file_content
        file_content, err = core.utils.get_file(config.auth_file)
        if file_content then
            auth_config = core.json.decode(file_content)
        end
    end

    if err then
        return nil, err
    end

    return auth_config
end


local function get_logger_buffer(conf, ctx)
    local oauth_client = google_oauth:new(auth_config_cache)

    local process = function(entries)
        return send_to_google(oauth_client, entries)
    end

    local config = {
        name = conf.name or plugin_name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    local buffer, err = batch_processor:new(process, config)

    if not buffer then
        return nil, "error when creating the batch processor: " .. err
    end

    return buffer
end


local function get_utc_timestamp()
    ngx_update_time()
    local now = tostring(ngx_now())
    local pos = core.string.rfind_char(now, ".", #now - 1)
    local second = now
    local millisecond = 0
    if pos then
        second = sub_str(now, 1, pos - 1)
        millisecond = sub_str(now, pos + 1)
    end
    return os_date("!%Y-%m-%dT%T.", second) .. core.string.format("%03dZ", millisecond)
end


local function get_logger_entry(conf)
    if not auth_config_cache then
        local auth_config, err = get_auth_config(conf)
        if err or not auth_config.project_id or not auth_config.private_key then
            return nil, "failed to get google authentication configuration" .. err
        end

        auth_config_cache = auth_config
    end

    local entry = log_util.get_full_log(ngx, conf)
    local google_entry = {
        httpRequest = {
            requestMethod = entry.request.method,
            requestUrl = entry.request.url,
            requestSize = entry.request.size,
            status = entry.response.status,
            responseSize = entry.response.size,
            userAgent = entry.request.headers and entry.request.headers["user-agent"],
            remoteIp = entry.client_ip,
            serverIp = entry.upstream,
            latency = tostring(core.string.format("%0.3f", entry.latency / 1000)) .. "s"
        },
        jsonPayload = {
            route_id = entry.route_id,
            service_id = entry.service_id,
        },
        labels = {
            source = "apache-apisix-google-logging"
        },
        timestamp = get_utc_timestamp(),
        resource = conf.resource,
        insertId = entry.request.id,
        logName = core.string.format("projects/%s/logs/%s", auth_config_cache.project_id, conf.log_id)
    }

    return google_entry
end


local _M = {
    version = 0.1,
    priority = 407,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.log(conf, ctx)
    local entry, err = get_logger_entry(conf)
    if err then
        core.log.error(err)
        return
    end

    if not stale_timer_running then
        -- run the timer every 15 minutes if any log is present
        ngx_timer_at(900, remove_stale_objects)
        stale_timer_running = true
    end

    local log_buffer = buffers[conf]
    if log_buffer then
        log_buffer:push(entry)
        return
    end

    log_buffer, err = get_logger_buffer(conf, ctx)

    if err then
        core.log.error(err)
        return
    end

    buffers[conf] = log_buffer
    log_buffer:push(entry)
end


return _M
