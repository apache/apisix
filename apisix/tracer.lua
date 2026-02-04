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
        local root_span = span.new()
        tracing = tablepool.fetch("tracing", 0, 8)
        tracing.spans = tablepool.fetch("tracing_spans", 20, 0)
        tracing.root_span = root_span
        tracing.current_span = root_span
        table.insert(tracing.spans, root_span)
        root_span.id = 1
        ctx.tracing = tracing
    end
    if tracing.skip then
        return
    end

    local spans = tracing.spans
    local sp = span.new(name, kind)

    table.insert(spans, sp)
    local id = #spans
    sp.id = id
    local parent = tracing.current_span
    if parent then
        sp:set_parent(parent.id)
        parent:append_child(id)
    end
    tracing.current_span = sp
    return sp
end


local function finish_span(spans, sp, code, message)
    if not sp or sp.end_time then
        return
    end
    for _, id in ipairs(sp.child_ids or {}) do
        finish_span(spans, spans[id])
    end
    if code then
        sp:set_status(code, message)
    end
    sp:finish()
end


function _M.finish(ctx, sp, code, message)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end

    sp = sp or tracing.current_span
    if not sp then
        return
    end

    finish_span(tracing.spans, sp, code, message)
    if sp == tracing.root_span then
        return
    end
    tracing.current_span = tracing.spans[sp.parent_id]
end


function _M.release(ctx)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end

    for _, sp in ipairs(tracing.spans) do
        sp:release()
    end
    tablepool.release("tracing_spans", tracing.spans)
    tablepool.release("tracing", tracing)
end


function _M.finish_all(ctx, code, message)
    local tracing = ctx and ctx.tracing
    if not tracing then
        return
    end

    local spans = tracing.spans
    tracing.current_span = tracing.root_span
    for _, id in ipairs(tracing.root_span.child_ids or {}) do
        finish_span(spans, spans[id], code, message)
    end
end


return _M
