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
local tablepool = require("tablepool")
local span = require("apisix.utils.span")
local noop_span = require("apisix.utils.noop_span").new()
local span_kind = require("opentelemetry.trace.span_kind")
local span_status = require("opentelemetry.trace.span_status")
local local_conf = require("apisix.core.config_local").local_conf()
local ipairs = ipairs
local ngx = ngx

local enable_tracing = false
if ngx.config.subsystem == "http" and type(local_conf.apisix.tracing) == "boolean" then
    enable_tracing = local_conf.apisix.tracing
end

local _M = {
    kind = span_kind,
    status = span_status,
}

function _M.start(ctx, name, kind)
    if not enable_tracing then
        return noop_span
    end

    local tracing = ctx.tracing
    if not tracing then
        tracing = tablepool.fetch("tracing", 0, 8)
        tracing.spans = tablepool.fetch("tracing_spans", 20, 0)
        ctx.tracing = tracing
        -- create a dummy root span as the invisible parent of all top-level spans
        span.new(ctx, "root", nil)
    end
    if tracing.skip then
        return noop_span
    end

    local sp = span.new(ctx, name, kind)
    return sp
end


function _M.finish_all(ctx, code, message)
    local tracing = ctx.tracing
    if not tracing or not tracing.current_span then
        return
    end

    tracing.current_span:set_status(code, message)
    tracing.current_span:finish(ctx)

    while tracing.current_span.parent_id do
        tracing.current_span = tracing.spans[tracing.current_span.parent_id]
        tracing.current_span:finish(ctx)
    end
end


function _M.release(ctx)
    local tracing = ctx.tracing
    if not tracing then
        return
    end

    for _, sp in ipairs(tracing.spans) do
        sp:release()
    end
    tablepool.release("tracing_spans", tracing.spans)
    tablepool.release("tracing", tracing)
end


return _M
