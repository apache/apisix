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

local core           = require("apisix.core")
local http           = require("resty.http")
local log_util       = require("apisix.utils.log-util")
local bp_manager_mod = require("apisix.utils.batch-processor-manager")

local ngx            = ngx
local str_format     = core.string.format
local math_random    = math.random

local plugin_name = "etcd-logger-test"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

local schema = {
    type = "object",
    properties = {
        auth = {
            type = "object",
            properties = {
                username = {
                    type = "string",
                    minLength = 1,
                    description = "the username to authenticate to etcd"
                },
                password = {
                    type = "string",
                    minLength = 1,
                    description = "the password to authenticate to etcd"
                },
            },
            required = {"username", "password"},
        },
        etcd = {
            type = "object",
            properties = {
                urls = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                        pattern = "[^/]$",
                    },
                    description = "the etcd server URLs, e.g. http://<host>:<port>",
                },
                key_prefix = {
                    type = "string",
                    default = "/apisix/logs",
                    description = "the prefix of the key to store logs in etcd"
                },
                ttl        = {
                    type = "integer",
                    minimum = 0,
                    default = 0,
                    description = "the time-to-live of the log key in etcd, in seconds. 0 means no ttl"
                },
            },
            required = {"urls"},
        },
        log_format = {type = "object"},
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
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        http_methods = {
            type = "array",
            items = {type = "string"},
            default = {},
            description = "the HTTP methods to log. Empty array means all methods"
        }
    },
    encrypt_fields = {"auth.password"},
    required = {"auth", "etcd"},
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
    priority = 416,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end

    local ok, err = log_util.check_log_schema(conf)
    if not ok then
        return nil, err
    end

    return ok
end


local function should_log(conf, method)
    if not conf.http_methods or #conf.http_methods == 0 then
        return true
    end
    for _, m in ipairs(conf.http_methods) do
        if m == method then
            return true
        end
    end
    return false
end


function _M.access(conf, ctx)
    ctx.should_log = should_log(conf, ctx.var.request_method)
end


function _M.body_filter(conf, ctx)
    if ctx.should_log then
        log_util.collect_body(conf, ctx)
    end
end


local function etcd_authenticate(conf)
    local httpc = http.new()
    if not httpc then
        return nil, "failed to create http client"
    end
    httpc:set_timeout(conf.timeout * 1000)

    local uri = conf.etcd.urls[math_random(#conf.etcd.urls)]

    local res, err = httpc:request_uri(uri .. "/v3/auth/authenticate", {
        method = "POST",
        body = core.json.encode({
            name = conf.auth.username,
            password = conf.auth.password,
        }),
        headers = {
            ["Content-Type"] = "application/json",
        },
        ssl_verify = conf.ssl_verify,
    })

    if not res then
        return nil, err
    end

    local body, err = core.json.decode(res.body)
    if not body then
        return nil, str_format("failed to parse etcd auth response: %s", err)
    end
    if not body.token then
        return nil, "no token returned by etcd"
    end

    return body.token
end

local function etcd_lease(conf, token)
    local httpc = http.new()
    if not httpc then
        return nil, "failed to create http client"
    end
    httpc:set_timeout(conf.timeout * 1000)

    local uri = conf.etcd.urls[math_random(#conf.etcd.urls)]

    if conf.etcd.ttl > 0 then
        local res, err = httpc:request_uri(uri .. "/v3/lease/grant", {
            method = "POST",
            body = core.json.encode({ TTL = conf.etcd.ttl }),
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = token
            },
            ssl_verify = conf.ssl_verify,
        })
        if not res then
            return nil, str_format("failed to grant etcd lease: %s", err)
        end
        local body = core.json.decode(res.body)
        return body.ID
    end
end


local function send_to_etcd(conf, entries)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    if not httpc then
        return nil, "failed to create http client"
    end

    local token, err = etcd_authenticate(conf)
    if not token then
        return nil, str_format("cannot send to etcd, authentication failed: %s", err)
    end

    local lease, err = etcd_lease(conf, token)
    if err then
        return nil, str_format("cannot send to etcd, failed to get lease: %s", err)
    end

    for _, entry in ipairs(entries) do
        local uri = conf.etcd.urls[math_random(#conf.etcd.urls)]
        entry.lease = lease
        local body = core.json.encode(entry)
        core.log.info("uri: ", uri, ", body: ", body)

        local res, err = httpc:request_uri(uri .. "/v3/kv/put", {
            method = "POST",
            body = body,
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = token
            },
            ssl_verify = conf.ssl_verify,
        })

        if not res then
            return nil, str_format("failed to send log to etcd: %s", err)
        end
        if res.status ~= 200 then
            return nil, str_format("etcd returned non-2xx status: %d body: %s", res.status, res.body)
        end
    end

    return true
end

local function get_logger_entry(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)
    local key = string.format("%s/%d-%d",
        conf.etcd.key_prefix,
        ngx.now(),
        math.random(10000, 99999)
    )
    local data = {
        key = ngx.encode_base64(key),
        value = ngx.encode_base64(core.json.encode(entry))
    }
    return data
end

function _M.log(conf, ctx)
    if not ctx.should_log then
        return
    end

    local entry = get_logger_entry(conf, ctx)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_etcd(conf, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end

return _M
