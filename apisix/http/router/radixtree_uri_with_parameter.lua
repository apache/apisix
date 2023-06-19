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
local base_router = require("apisix.http.route")
local router = require("apisix.router")


local _M = {}


    local match_opts = {}
function _M.match(api_ctx)
    return _M.matching(api_ctx)
end


function _M.matching(api_ctx)
    core.log.info("route match mode: radixtree_uri_with_parameter")
    return base_router.match_uri(router.uri_router, match_opts, api_ctx)
end

return _M
