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

local core            = require("apisix.core")
local tostring        = tostring
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local google_oauth    = require("apisix.plugins.google-cloud-logging.oauth")


local lrucache = core.lrucache.new({
    type = "plugin",
})

local plugin_name = "google-cloud-logging"
local batch_processor_manager = bp_manager_mod.new(plugin_name)
local schema = {
    type = "object",
    properties = {
        auth_config = {
            type = "object",
            properties = {
                private_key = { type = "string" },
                project_id = { type = "string" },
                token_uri = {
                    type = "string",
                    default = "https://oauth2.googleapis.com/token"
                },
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
                entries_uri = {
                    type = "string",
                    default = "https://logging.googleapis.com/v2/entries:write"
                },
            },
            required = { "private_key", "project_id", "token_uri" }
        },
        ssl_verify = {
            type = "boolean",
            default = true
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
        -- https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry
        log_id = {
            type = "string",
            default = "apisix.apache.org%2Flogs"
        },
        log_format = {type = "object"},
    },
    oneOf = {
        { required = { "auth_config" } },
        { required = { "auth_file" } },
    },
    encrypt_fields = {"auth_config.private_key"},
}

local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local function send_to_google(oauth, entries)
    local http_new = http.new()
    local access_token = oauth:generate_access_token()
    if not access_token then
        return nil, "failed to get google oauth token"
    end

    local res, err = http_new:request_uri(oauth.entries_uri, {
        ssl_verify = oauth.ssl_verify,
        method = "POST",
        body = core.json.encode({
            entries = entries,
            partialSuccess = false,
        }),
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = (oauth.access_token_type or "Bearer") .. " " .. access_token,
        },
    })

    if not res then
        return nil, "failed to write log to google, " .. err
    end

    if res.status ~= 200 then
        return nil, res.body
    end

    return res.body
end


local function fetch_oauth_conf(conf)
    if conf.auth_config then
        return conf.auth_config
    end

    if not conf.auth_file then
        return nil, "configuration is not defined"
    end

    local file_content, err = core.io.get_file(conf.auth_file)
    if not file_content then
        return nil, "failed to read configuration, file: " .. conf.auth_file .. " err: " .. err
    end

    local config_tab
    config_tab, err = core.json.decode(file_content)
    if not config_tab then
        return nil, "config parse failure, data: " .. file_content .. " , err: " .. err
    end

    return config_tab
end


local function create_oauth_object(conf)
    local auth_conf, err = fetch_oauth_conf(conf)
    if not auth_conf then
        return nil, err
    end

    return google_oauth:new(auth_conf, conf.ssl_verify)
end


local function get_logger_entry(conf, ctx, oauth)
    local entry, customized = log_util.get_log_entry(plugin_name, conf, ctx)
    local google_entry
    if not customized then
        google_entry = {
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
        }
    else
        google_entry = {
            jsonPayload = entry,
        }
    end

    google_entry.labels = {
        source = "apache-apisix-google-cloud-logging"
    }
    google_entry.timestamp = log_util.get_rfc3339_zulu_timestamp()
    google_entry.resource = conf.resource
    google_entry.insertId = ctx.var.request_id
    google_entry.logName = core.string.format("projects/%s/logs/%s", oauth.project_id, conf.log_id)

    return google_entry
end


local _M = {
    version = 0.1,
    priority = 407,
    name = plugin_name,
    metadata_schema = metadata_schema,
    schema = batch_processor_manager:wrap_schema(schema),
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    return core.schema.check(schema, conf)
end


function _M.log(conf, ctx)
    local oauth, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                create_oauth_object, conf)
    if not oauth then
        core.log.error("failed to fetch google-cloud-logging.oauth object: ", err)
        return
    end

    local entry = get_logger_entry(conf, ctx, oauth)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_google(oauth, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end


return _M
