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
local table = require("apisix.core.table")
local tablepool = require("tablepool")
local stack = require("apisix.utils.stack")
local span = require("apisix.utils.span")
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
    span_state = {},
}

function _M.start(ctx, name, kind)
    if not enable_tracing then
        return
    end

    local tracing = ctx and ctx.tracing
    if not tracing then
        tracing = tablepool.fetch("tracing", 0, 8)
        tracing.context = stack.new()
        tracing.spans = tablepool.fetch("tracing_spans", 20, 0)
        ctx.tracing = tracing
    end
    if tracing.skip then
        return
    end

    local spans = tracing.spans
    local context = tracing.context

    table.insert(spans, span.new(name, kind))
    local idx = #spans

    if not context:is_empty() then
        local parent_idx = context:peek()
        local parent = spans[parent_idx]
        parent:append_child(idx)
    end
    context:push(idx)
end


local function finish_span(tracing, code, message)
    local sp_idx = tracing.context:pop()
    if not sp_idx then
        return
    end
    local sp = tracing.spans[sp_idx]
    if code then
        sp:set_status(code, message)
    end
    sp:finish()
end


function _M.finish(ctx, code, message)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end
    finish_span(tracing, code, message)
end


function _M.finish_all(ctx, code, message)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end
    while not tracing.context:is_empty() do
        finish_span(tracing, code, message)
    end
end


function _M.release(ctx)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end

    while not tracing.context:is_empty() do
        finish_span(tracing)
    end

    for _, sp in ipairs(tracing.spans) do
        sp:release()
    end
    tablepool.release("tracing_spans", tracing.spans)
    tablepool.release("tracing", tracing)
end


return _M
