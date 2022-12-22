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
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local plugin          = require("apisix.plugin")

local ngx             = ngx
local str_format      = core.string.format

local plugin_name = "elasticsearch-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)


local schema = {
    type = "object",
    properties = {
        endpoint_addr = {
            type = "string",
            pattern = "[^/]$",
        },
        field = {
            type = "object",
            properties = {
                index = { type = "string"},
                type = { type = "string"}
            },
            required = {"index"}
        },
        auth = {
            type = "object",
            properties = {
                username = {
                    type = "string",
                    minLength = 1
                },
                password = {
                    type = "string",
                    minLength = 1
                },
            },
            required = {"username", "password"},
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 10
        },
        ssl_verify = {
            type = "boolean",
            default = true
        }
    },
    encrypt_fields = {"auth.password"},
    required = { "endpoint_addr", "field" },
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 413,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function get_logger_entry(conf, ctx)
    local entry
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))
    if metadata and metadata.value.log_format
        and core.table.nkeys(metadata.value.log_format) > 0
    then
        entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
        core.log.info("custom log format entry: ", core.json.delay_encode(entry))
    else
        entry = log_util.get_full_log(ngx, conf)
        core.log.info("full log entry: ", core.json.delay_encode(entry))
    end

    return core.json.encode({
            create = {
                _index = conf.field.index,
                _type = conf.field.type
            }
        }) .. "\n" ..
        core.json.encode(entry) .. "\n"
end


local function send_to_elasticsearch(conf, entries)
    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http error: %s", err)
    end

    local uri = conf.endpoint_addr .. "/_bulk"
    local body = core.table.concat(entries, "")
    local headers = {["Content-Type"] = "application/x-ndjson"}
    if conf.auth then
        local authorization = "Basic " .. ngx.encode_base64(
            conf.auth.username .. ":" .. conf.auth.password
        )
        headers["Authorization"] = authorization
    end

    core.log.info("uri: ", uri, ", body: ", body)

    httpc:set_timeout(conf.timeout * 1000)
    local resp, err = httpc:request_uri(uri, {
        ssl_verify = conf.ssl_verify,
        method = "POST",
        headers = headers,
        body = body
    })
    if not resp then
        return false, err
    end

    if resp.status ~= 200 then
        return false, str_format("elasticsearch server returned status: %d, body: %s",
        resp.status, resp.body or "")
    end

    return true
end


function _M.log(conf, ctx)
    local entry = get_logger_entry(conf, ctx)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_elasticsearch(conf, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end


return _M
