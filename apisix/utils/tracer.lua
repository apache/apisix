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
local stack = require("apisix.utils.stack")
local span = require("apisix.utils.span")
local span_kind = require("opentelemetry.trace.span_kind")
local span_status = require("opentelemetry.trace.span_status")
local table = table
local pairs = pairs

local _M = {
    kind = span_kind,
    status = span_status,
}


function _M.new_span(name, kind)
    local ctx = ngx.ctx
    if not ctx._apisix_spans then
        ctx._apisix_spans = {}
    end
    if not ctx._apisix_span_stack then
        ctx._apisix_span_stack = stack.new()
    end
    local sp = span.new(name, kind)
    if ctx._apisix_skip_tracing then
        return sp
    end
    if ctx._apisix_span_stack:is_empty() then
        table.insert(ctx._apisix_spans, sp)
    else
        local parent_span = ctx._apisix_span_stack:peek()
        parent_span:append_child(sp)
    end
    ctx._apisix_span_stack:push(sp)
    return sp
end


function _M.finish_current_span(code, message)
    if not ngx.ctx._apisix_span_stack then
        return
    end
    local sp = ngx.ctx._apisix_span_stack:pop()
    if code then
        sp:set_status(code, message)
    end
    sp:finish()
end

function _M.finish_all_spans(code, message)
    local apisix_spans = ngx.ctx._apisix_spans
    if not apisix_spans then
        return
    end

    for _, sp in pairs(apisix_spans) do
        if code then
            sp:set_status(code, message)
        end
        sp:finish()
    end
end


return _M
