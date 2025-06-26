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

local ngx             = ngx
local str_format      = core.string.format
local math_random     = math.random

local plugin_name = "elasticsearch-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

local schema = {
    type = "object",
    properties = {
        -- deprecated, use "endpoint_addrs" instead
        endpoint_addr = {
            type = "string",
            pattern = "[^/]$",
        },
        endpoint_addrs = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = "[^/]$",
            },
        },
        field = {
            type = "object",
            properties = {
                index = { type = "string"},
            },
            required = {"index"}
        },
        log_format = {type = "object"},
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
        },
        include_req_body = {type = "boolean", default = false},
        include_req_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        include_resp_body = { type = "boolean", default = false },
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
    },
    encrypt_fields = {"auth.password"},
    oneOf = {
        {required = {"endpoint_addr", "field"}},
        {required = {"endpoint_addrs", "field"}}
    },
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = {
            type = "object"
        }
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

    local check = {"endpoint_addrs"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)
    return core.schema.check(schema, conf)
end


local function get_es_major_version(uri, conf)
    local httpc = http.new()
    if not httpc then
        return nil, "failed to create http client"
    end
    local headers = {}
    if conf.auth then
        local authorization = "Basic " .. ngx.encode_base64(
            conf.auth.username .. ":" .. conf.auth.password
        )
        headers["Authorization"] = authorization
    end
    httpc:set_timeout(conf.timeout * 1000)
    local res, err = httpc:request_uri(uri, {
        ssl_verify = conf.ssl_verify,
        method = "GET",
        headers = headers,
    })
    if not res then
        return false, err
    end
    if res.status ~= 200 then
        return nil, str_format("server returned status: %d, body: %s",
            res.status, res.body or "")
    end
    local json_body, err = core.json.decode(res.body)
    if not json_body then
        return nil, "failed to decode response body: " .. err
    end
    if not json_body.version or not json_body.version.number then
        return nil, "failed to get version from response body"
    end

    local major_version = json_body.version.number:match("^(%d+)%.")
    if not major_version then
        return nil, "invalid version format: " .. json_body.version.number
    end

    return major_version
end


local function get_logger_entry(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)
    local body = {
        index = {
            _index = conf.field.index
        }
    }
    -- for older version type is required
    if conf._version == "6" or conf._version == "5" then
        body.index._type = "_doc"
    end
    return core.json.encode(body) .. "\n" ..
        core.json.encode(entry) .. "\n"
end

local function fetch_and_update_es_version(conf)
    if conf._version then
        return
    end
    local selected_endpoint_addr
    if conf.endpoint_addr then
        selected_endpoint_addr = conf.endpoint_addr
    else
        selected_endpoint_addr = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]
    end
    local major_version, err = get_es_major_version(selected_endpoint_addr, conf)
    if err then
        core.log.error("failed to get Elasticsearch version: ", err)
        return
    end
    conf._version = major_version
end


local function send_to_elasticsearch(conf, entries)
    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http error: %s", err)
    end
    fetch_and_update_es_version(conf)
    local selected_endpoint_addr
    if conf.endpoint_addr then
        selected_endpoint_addr = conf.endpoint_addr
    else
        selected_endpoint_addr = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]
    end
    local uri = selected_endpoint_addr .. "/_bulk"
    local body = core.table.concat(entries, "")
    local headers = {
        ["Content-Type"] = "application/x-ndjson",
        ["Accept"] = "application/vnd.elasticsearch+json"
    }
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


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end

function _M.access(conf)
    -- fetch_and_update_es_version will call ES server only the first time
    -- so this should not amount to considerable overhead
    fetch_and_update_es_version(conf)
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
