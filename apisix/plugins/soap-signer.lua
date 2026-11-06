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
local request = require("apisix.plugins.signing.request")
local signer = require("apisix.plugins.soap-signer.signer")

local plugin_name = "soap-signer"

local schema = {
    type = "object",
    additionalProperties = false,
    properties = {
        credentials = {
            type = "object",
            additionalProperties = false,
            properties = {
                certificate = {type = "string", minLength = 1},
                private_key = {type = "string", minLength = 1},
            },
            required = {"certificate", "private_key"},
        },
        signature = {
            type = "object",
            additionalProperties = false,
            default = {},
            properties = {
                algorithm = {
                    type = "string",
                    enum = {"rsa-sha1", "rsa-sha256"},
                    default = "rsa-sha256",
                },
                key_info = {
                    type = "string",
                    enum = {"binary_security_token", "none"},
                    default = "binary_security_token",
                },
            },
        },
        soap = {
            type = "object",
            additionalProperties = false,
            default = {},
            properties = {
                version = {
                    type = "string",
                    enum = {"auto", "1.1", "1.2"},
                    default = "auto",
                },
                must_understand = {type = "boolean", default = true},
            },
        },
        timestamp = {
            type = "object",
            additionalProperties = false,
            default = {},
            properties = {
                ttl_seconds = {
                    type = "integer",
                    minimum = 1,
                    maximum = 86400,
                    default = 300,
                },
            },
        },
        request = {
            type = "object",
            additionalProperties = false,
            default = {},
            properties = {
                methods = {
                    type = "array",
                    minItems = 1,
                    uniqueItems = true,
                    items = {type = "string", minLength = 1},
                    default = {"POST"},
                },
                content_types = {
                    type = "array",
                    minItems = 1,
                    uniqueItems = true,
                    items = {type = "string", minLength = 1},
                    default = {"text/xml", "application/soap+xml", "application/xml"},
                },
                max_body_bytes = {
                    type = "integer",
                    minimum = 1024,
                    maximum = 67108864,
                    default = 5242880,
                },
            },
        },
    },
    encrypt_fields = {"credentials.private_key"},
    required = {"credentials"},
}

local _M = {
    version = 0.1,
    priority = 1027,
    name = plugin_name,
    schema = schema,
}


local function set_default(target, key, value)
    if target[key] == nil then
        target[key] = value
    end
end


local function normalize_conf(original)
    local conf = core.table.deepcopy(original or {})
    conf.signature = conf.signature or {}
    set_default(conf.signature, "algorithm", "rsa-sha256")
    set_default(conf.signature, "key_info", "binary_security_token")
    conf.soap = conf.soap or {}
    set_default(conf.soap, "version", "auto")
    set_default(conf.soap, "must_understand", true)
    conf.timestamp = conf.timestamp or {}
    set_default(conf.timestamp, "ttl_seconds", 300)
    conf.request = conf.request or {}
    set_default(conf.request, "methods", {"POST"})
    set_default(conf.request, "content_types",
                {"text/xml", "application/soap+xml", "application/xml"})
    set_default(conf.request, "max_body_bytes", 5242880)
    return conf
end


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    conf = normalize_conf(conf)
    return request.rewrite(plugin_name, conf, ctx, signer.sign)
end


return _M