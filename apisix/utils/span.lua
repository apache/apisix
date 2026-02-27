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
local util = require("opentelemetry.util")
local span_status = require("opentelemetry.trace.span_status")
local setmetatable = setmetatable
local table = table
local new_tab = require("table.new")
local select = select
local pool_name = "opentelemetry_span"
local update_time = ngx.update_time

local _M = {}


local mt = {
    __index = _M
}

local function get_time()
    update_time()
    return util.time_nano()
end



local function append_child(sp, child_id)
    if not sp.child_ids then
        sp.child_ids = new_tab(10, 0)
    end
    table.insert(sp.child_ids, child_id)
end


local function set_parent(sp, parent_id)
    sp.parent_id = parent_id
end


function _M.new(ctx, name, kind)
    local tracing = ctx.tracing

    local self = tablepool.fetch(pool_name, 0, 16)
    self.start_time = get_time()
    self.name = name
    self.kind = kind

    table.insert(tracing.spans, self)
    local id = #tracing.spans
    self.id = id

    local parent = tracing.current_span
    if parent then
        set_parent(self, parent.id)
        append_child(parent, id)
    else
        tracing.root_span = self
    end

    ctx.tracing.current_span = self
    return setmetatable(self, mt)
end


function _M.set_status(self, code, message)
    code = span_status.validate(code)
    local status = self.status
    if not status then
        status = {
            code = code,
            message = ""
        }
        self.status = status
    else
        status.code = code
    end

    if code == span_status.ERROR then
        status.message = message
    end
end


function _M.set_attributes(self, ...)
    if not self.attributes then
        self.attributes = new_tab(10, 0)
    end
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        table.insert(self.attributes, attr)
    end
end


function _M.finish(self, ctx)
    local tracing = ctx.tracing
    self.end_time = get_time()
    if not self.parent_id then
        return
    end
    tracing.current_span = tracing.spans[self.parent_id]
end


function _M.release(self)
    tablepool.release(pool_name, self)
end


return _M
