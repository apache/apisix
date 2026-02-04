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


function _M.new(name, kind)
    local self = tablepool.fetch(pool_name, 0, 16)
    self.start_time = get_time()
    self.name = name
    self.kind = kind
    return setmetatable(self, mt)
end


function _M.append_child(self, child_id)
    if not self.child_ids then
        self.child_ids = table.new(10, 0)
    end
    table.insert(self.child_ids, child_id)
end


function _M.set_parent(self, parent_id)
    self.parent_id = parent_id
end


function _M.release(self)
    tablepool.release(pool_name, self)
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
        self.attributes = table.new(10, 0)
    end
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        table.insert(self.attributes, attr)
    end
end


function _M.finish(self)
    self.end_time = get_time()
end


return _M
