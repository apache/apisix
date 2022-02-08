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
local router = require("apisix.router")

local schema = {
    type = "object",
    properties = {
        uri = {type = "string"},
    },
}


local _M = {
    version = 0.1,
    priority = 501,
    name = "public-api",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    -- overwrite the uri in the ctx when the user has set the target uri
    ctx.var.uri = conf.uri or ctx.var.uri

    -- perform route matching
    if router.api.match(ctx) then
        return
    end

    return 404
end


return _M
