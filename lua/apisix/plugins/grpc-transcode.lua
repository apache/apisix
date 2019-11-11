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
local ngx         = ngx
local core        = require("apisix.core")
local plugin_name = "grpc-transcode"
local proto       = require("apisix.plugins.grpc-transcode.proto")
local request     = require("apisix.plugins.grpc-transcode.request")
local response    = require("apisix.plugins.grpc-transcode.response")


local schema = {
    type = "object",
    additionalProperties = true
}


local _M = {
    version = 0.1,
    priority = 506,
    name = plugin_name,
    schema = schema,
}


function _M.init()
    proto.init()
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("conf: ", core.json.delay_encode(conf))

    local proto_id = conf.proto_id
    if not proto_id then
        core.log.error("proto id miss: ", proto_id)
        return
    end

    local proto_obj, err = proto.fetch(proto_id)
    if err then
        core.log.error("proto load error: ", err)
        return
    end

    local ok, err = request(proto_obj, conf.service, conf.method)
    if not ok then
        core.log.error("transform request error: ", err)
        return
    end

    ctx.proto_obj = proto_obj
end


function _M.header_filter(conf, ctx)
    if ngx.status >= 300 then
        return
    end

    ngx.header["Content-Type"] = "application/json"
    ngx.header["Trailer"] = {"grpc-status", "grpc-message"}
end


function _M.body_filter(conf, ctx)
    if ngx.status >= 300 then
        return
    end

    local proto_obj = ctx.proto_obj
    if not proto_obj then
        return
    end

    local err = response(proto_obj, conf.service, conf.method)
    if err then
        core.log.error("transform response error: ", err)
        return
    end
end


return _M
