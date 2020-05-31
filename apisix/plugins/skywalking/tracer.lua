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
local span = require("skywalking.span")
local tracing_context = require("skywalking.tracing_context")
local span_layer = require("skywalking.span_layer")
local sw_segment = require('skywalking.segment')

local pairs = pairs
local ngx = ngx

-- Constant pre-defined in SkyWalking main repo
-- 84 represents Nginx
local NGINX_COMPONENT_ID = 6000

local _M = {}

function _M.start(ctx, endpoint, upstream_name)
    local context
    -- TODO: use lrucache for better performance
    local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
    local instance_id = tracing_buffer:get(endpoint .. '_instance_id')
    local service_id = tracing_buffer:get(endpoint .. '_service_id')

    if service_id and instance_id then
        context = tracing_context.new(service_id, instance_id)
    else
        context = tracing_context.newNoOP()
    end

    local context_carrier = {}
    context_carrier["sw6"] = ngx.req.get_headers()["sw6"]
    local entry_span = tracing_context.createEntrySpan(context, ctx.var.uri, nil, context_carrier)
    span.start(entry_span, ngx.now() * 1000)
    span.setComponentId(entry_span, NGINX_COMPONENT_ID)
    span.setLayer(entry_span, span_layer.HTTP)

    span.tag(entry_span, 'http.method', ngx.req.get_method())
    span.tag(entry_span, 'http.params', ctx.var.scheme .. '://'
                                        .. ctx.var.host .. ctx.var.request_uri)

    context_carrier = {}
    local exit_span = tracing_context.createExitSpan(context,
                                                    ctx.var.upstream_uri,
                                                    entry_span,
                                                    upstream_name,
                                                    context_carrier)
    span.start(exit_span, ngx.now() * 1000)
    span.setComponentId(exit_span, NGINX_COMPONENT_ID)
    span.setLayer(exit_span, span_layer.HTTP)

    for name, value in pairs(context_carrier) do
        ngx.req.set_header(name, value)
    end

    -- Push the data in the context
    ctx.sw_tracing_context = context
    ctx.sw_entry_span = entry_span
    ctx.sw_exit_span = exit_span

    core.log.debug("push data into skywalking context")
end

function _M.finish(ctx)
    -- Finish the exit span when received the first response package from upstream
    if ctx.sw_exit_span then
        span.finish(ctx.sw_exit_span, ngx.now() * 1000)
        ctx.sw_exit_span = nil
    end
end

function _M.prepareForReport(ctx, endpoint)
    if ctx.sw_entry_span then
        span.finish(ctx.sw_entry_span, ngx.now() * 1000)
        local status, segment = tracing_context.drainAfterFinished(ctx.sw_tracing_context)
        if status then
            local segment_json = core.json.encode(sw_segment.transform(segment))
            core.log.debug('segment = ', segment_json)

            local tracing_buffer = ngx.shared['skywalking-tracing-buffer']
            local length = tracing_buffer:lpush(endpoint .. '_segment', segment_json)
            core.log.debug('segment buffer size = ', length)
        end
    end
end

return _M
