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
local require = require
local bad_request = ngx.HTTP_BAD_REQUEST
local internal_server_error = ngx.HTTP_INTERNAL_SERVER_ERROR

local _M = {}

function _M.before_proxy(conf, ctx)
    local ai_instance = ctx.picked_ai_instance
    local ai_driver = require("apisix.plugins.ai-drivers." .. ai_instance.provider)

    local request_body, err = ai_driver.validate_request(ctx)
    if not request_body then
        return bad_request, err
    end

    local extra_opts = {
        endpoint = core.table.try_read_attr(ai_instance, "override", "endpoint"),
        query_params = ai_instance.auth.query or {},
        headers = (ai_instance.auth.header or {}),
        model_options = ai_instance.options,
    }

    if request_body.stream then
        request_body.stream_options = {
            include_usage = true
        }
    end

    local res, err = ai_driver:request(conf, request_body, extra_opts)
    if not res then
        core.log.warn("failed to send request to AI service: ", err)
        if core.string.find(err, "timeout") then
            return 504
        end
        return internal_server_error
    end

    return ai_driver.read_response(ctx, res)
end


return _M
