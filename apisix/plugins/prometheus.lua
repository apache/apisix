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
local ngx = ngx
local core = require("apisix.core")
local exporter = require("apisix.plugins.prometheus.exporter")


local plugin_name = "prometheus"
local default_export_uri = "/apisix/prometheus/metrics"
local schema = {
    type = "object",
    additionalProperties = false,
}


local _M = {
    version = 0.2,
    priority = 500,
    name = plugin_name,
    log  = exporter.log,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function get_api(called_by_api_router)
    local export_uri = default_export_uri
    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr",
                                          plugin_name)
    if attr and attr.export_uri then
        export_uri = attr.export_uri
    end

    local api = {
        methods = {"GET"},
        uri = export_uri,
        handler = exporter.collect
    }

    if not called_by_api_router then
        return api
    end

    if attr.enable_export_server then
        return {}
    end

    return {api}
end


function _M.api()
    return get_api(true)
end


function _M.export_metrics()
    local api = get_api(false)
    local uri = ngx.var.uri
    local method = ngx.req.get_method()

    if uri == api.uri and method == api.methods[1] then
        return api.handler()
    end

    return core.response.exit(404)
end


-- only for test
-- function _M.access()
--     ngx.say(exporter.metric_data())
-- end


return _M
