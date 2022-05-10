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
local require = require
local core = require("apisix.core")
local ok, apisix_ngx_client = pcall(require, "resty.apisix.client")


local schema = {
    type = "object",
    properties = {
        request_buffering = {
            type = "boolean",
            default = true,
        },
    },
}


local plugin_name = "proxy-control"
local _M = {
    version = 0.1,
    priority = 21990,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- we want to control proxy behavior before auth, so put the code under rewrite method
function _M.rewrite(conf, ctx)
    if not ok then
        core.log.error("need to build APISIX-Base to support proxy control")
        return 501
    end

    local request_buffering = conf.request_buffering
    if request_buffering  ~= nil then
        local ok, err = apisix_ngx_client.set_proxy_request_buffering(request_buffering)
        if not ok then
            core.log.error("failed to set request_buffering: ", err)
            return 503
        end
    end
end


return _M
