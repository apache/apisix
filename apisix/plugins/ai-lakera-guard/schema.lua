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
local binding = require("apisix.plugins.ai-protocols.binding")


local schema = {
    type = "object",
    properties = {
        api_key = {
            type = "string",
            minLength = 1,
            description = "Lakera Guard API key, sent as 'Authorization: Bearer'.",
        },
        lakera_endpoint = {
            type = "string",
            pattern = [[^https?://]],
            default = "https://api.lakera.ai/v2/guard",
            description = "Lakera Guard v2 endpoint.",
        },
        project_id = {
            type = "string",
            description = "Lakera project whose policy (detectors + thresholds) to apply.",
        },
        direction = {
            type = "string",
            enum = { "input", "output", "both" },
            default = "input",
            description = "Which traffic to scan: input (request), output (response), or both.",
        },
        action = {
            type = "string",
            enum = { "block", "alert" },
            default = "block",
            description = "How a flagged verdict is handled: block = deny the "
                          .. "request; alert = log-only shadow mode that passes "
                          .. "the request through. Affects flagged verdicts only; "
                          .. "Lakera API errors/timeouts stay governed by "
                          .. "fail_open even in alert mode.",
        },
        fail_open = {
            type = "boolean",
            default = false,
            description = "On Lakera error/timeout: false = fail-closed (deny), true = allow.",
        },
        fail_mode = binding.schema_property("skip"),
        timeout = {
            type = "integer",
            minimum = 1,
            default = 5000,
            description = "Lakera request timeout in milliseconds.",
        },
        ssl_verify = {
            type = "boolean",
            default = true,
            description = "Verify the TLS certificate of the Lakera endpoint.",
        },
        reveal_failure_categories = {
            type = "boolean",
            default = false,
            description = "Include the raw Lakera detector_types in the deny response.",
        },
        deny_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
            default = 200,
            description = "HTTP status returned on a block. Defaults to 200 so the "
                          .. "provider-compatible refusal parses as a normal "
                          .. "completion in client SDKs; set a 4xx to surface "
                          .. "blocks as HTTP errors instead.",
        },
        request_failure_message = {
            type = "string",
            default = "Request blocked by Lakera Guard",
            description = "Message returned when a request is blocked.",
        },
        response_failure_message = {
            type = "string",
            default = "Response blocked by Lakera Guard",
            description = "Message returned when an LLM response is blocked.",
        },
    },
    encrypt_fields = { "api_key" },
    required = { "api_key" },
}


local _M = {}


_M.schema = schema


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


return _M
