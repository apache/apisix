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
local process = require("ngx.process")

local always_on_sampler_new = require("opentelemetry.trace.sampling.always_on_sampler").new
local exporter_client_new = require("opentelemetry.trace.exporter.http_client").new
local otlp_exporter_new = require("opentelemetry.trace.exporter.otlp").new
local batch_span_processor_new = require("opentelemetry.trace.batch_span_processor").new
local tracer_provider_new = require("opentelemetry.trace.tracer_provider").new
local resource_new = require("opentelemetry.resource").new
local attr = require("opentelemetry.attribute")
local span_kind = require("opentelemetry.trace.span_kind")

local context = require("opentelemetry.context").new()

local _M = { version = 0.1 }

local hostname

function _M.init()
    if process.type() ~= "worker" then
        return
    end
    hostname = core.utils.gethostname()
end



local DebugTracerProvider = {}
DebugTracerProvider.__index = DebugTracerProvider

function DebugTracerProvider.new(collector_config, resource_attrs)
    local self = setmetatable({
        collector_config = collector_config or {
            address = "127.0.0.1:4318",
            request_timeout = 3,
            request_headers = {}
        },
        resource_attrs = resource_attrs or {},
        spans = {},  -- Buffered spans for this tracer instance
        is_reporting = false
    }, DebugTracerProvider)
    
    return self
end

function DebugTracerProvider:start_span(span_name, options)
    local span_id = core.utils.uuid()
    local trace_id = core.utils.uuid()
    local start_time = ngx.now() * 1000000000  -- Convert to nanoseconds
    
    local span = {
        id = span_id,
        trace_id = trace_id,
        name = span_name,
        start_time = start_time,
        end_time = nil,
        kind = options and options.kind or span_kind.internal,
        attributes = options and options.attributes or {},
        parent_span_id = options and options.parent_span_id,
        status = nil,
        events = {}
    }
    
    -- Store in buffered spans
    self.spans[span_id] = span
    
    return {
        span_id = span_id,
        trace_id = trace_id,
        name = span_name,
        context = context
    }
end

function DebugTracerProvider:finish_span(span_token, end_time)
    local span = self.spans[span_token.span_id]
    if span then
        span.end_time = end_time or (ngx.now() * 1000000000)
    end
    return span
end

function DebugTracerProvider:add_event(span_token, event_name, attributes)
    local span = self.spans[span_token.span_id]
    if span then
        table.insert(span.events, {
            name = event_name,
            time = ngx.now() * 1000000000,
            attributes = attributes or {}
        })
    end
end

function DebugTracerProvider:set_attributes(span_token, attributes)
    local span = self.spans[span_token.span_id]
    if span then
        for k, v in pairs(attributes) do
            span.attributes[k] = v
        end
    end
end

function DebugTracerProvider:set_status(span_token, status, description)
    local span = self.spans[span_token.span_id]
    if span then
        span.status = {
            code = status,
            description = description
        }
    end
end

function DebugTracerProvider:report_trace(debug_session_id)
    if self.is_reporting then
        core.log.warn("Debug tracer is already in reporting mode")
        return
    end
    
    self.is_reporting = true
    
    -- Create real OpenTelemetry tracer
    local real_tracer = self:_create_real_tracer(debug_session_id)
    
    -- Convert all buffered spans to real spans
    for span_id, buffered_span in pairs(self.spans) do
        if buffered_span.end_time then
            self:_convert_to_real_span(real_tracer, buffered_span)
        end
    end
    
    -- Force flush
    real_tracer.provider:force_flush()
    
    core.log.info("Debug trace reported for session: ", debug_session_id)
end

function DebugTracerProvider:_create_real_tracer(debug_session_id)
    -- Build resource attributes
    local resource_attrs = { attr.string("hostname", hostname) }
    
    -- Add service name if not provided
    if not self.resource_attrs["service.name"] then
        table.insert(resource_attrs, attr.string("service.name", "APISIX-Debug"))
    end
    
    -- Add debug session ID
    table.insert(resource_attrs, attr.string("debug.session.id", debug_session_id))
    
    -- Add custom resource attributes
    for k, v in pairs(self.resource_attrs) do
        if type(v) == "string" then
            table.insert(resource_attrs, attr.string(k, v))
        elseif type(v) == "number" then
            table.insert(resource_attrs, attr.double(k, v))
        elseif type(v) == "boolean" then
            table.insert(resource_attrs, attr.bool(k, v))
        end
    end
    
    -- Create real tracer
    local exporter = otlp_exporter_new(
        exporter_client_new(
            self.collector_config.address,
            self.collector_config.request_timeout,
            self.collector_config.request_headers
        )
    )
    
    local batch_span_processor = batch_span_processor_new(
        exporter,
        self.collector_config.batch_span_processor or {}
    )
    
    local sampler = always_on_sampler_new()  -- Always sample debug traces
    
    local tp = tracer_provider_new(batch_span_processor, {
        resource = resource_new(unpack(resource_attrs)),
        sampler = sampler,
    })
    
    return tp:tracer("apisix-debug-tracer")
end

function DebugTracerProvider:_convert_to_real_span(real_tracer, buffered_span)
    -- Start span with original timing
    local span_ctx = real_tracer:start(buffered_span.name, {
        kind = buffered_span.kind,
        attributes = buffered_span.attributes,
        start_time = buffered_span.start_time
    })
    
    local span = span_ctx:span()
    
    -- Add events
    for _, event in ipairs(buffered_span.events) do
        -- Note: OpenTelemetry Lua might not have direct event API
        -- We can add as attributes instead
        span:set_attributes(event.attributes)
    end
    
    -- Set status
    if buffered_span.status then
        span:set_status(buffered_span.status.code, buffered_span.status.description)
    end
    
    -- Finish with original end time
    span:finish(buffered_span.end_time)
end

function DebugTracerProvider:get_buffered_spans_count()
    local count = 0
    for _ in pairs(self.spans) do
        count = count + 1
    end
    return count
end

function _M.create_tracer_provider(collector_config, resource_attrs)
    return DebugTracerProvider.new(collector_config, resource_attrs)
end

return _M
