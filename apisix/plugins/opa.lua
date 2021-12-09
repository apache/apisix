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

local core   = require("apisix.core")
local http   = require("resty.http")
local helper = require("apisix.plugins.opa.helper")

local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        package = {type = "string"},
        decision = {type = "string", maxLength = 256},
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5}
    },
    required = {"host", "package", "decision"}
}


local _M = {
    version = 0.1,
    priority = 2001,
    name = "opa",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    local body = helper.build_opa_input(conf, ctx, "http")
    local params = {
        method = "POST",
        body = body,
        headers = {
            ["Content-Type"] = "application/json",
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local endpoint = conf.host .. "/v1/data/" .. conf.package .. "/" .. conf.decision

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(endpoint, params)

    -- block by default when decision is unavailable
    if not res or err then
        core.log.error("failed to process OPA decision, err: ", err)
        return 403
    end

    -- parse the results of the decision
    local ret = core.json.decode(res.body).result

    if not ret then
        return 403
    end
end


return _M
