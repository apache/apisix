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
local ipairs = ipairs
local pool_name = "opentelemetry_span"

local _M = {}


local mt = {
    __index = _M
}


function _M.new(name, kind)
    local self = tablepool.fetch(pool_name, 0, 8)
    self.name = name
    self.start_time = util.time_nano()
    self.end_time = 0
    self.kind = kind
    self.attributes = self.attributes or {}
    self.children = self.children or {}
    self.status = nil
    return setmetatable(self, mt)
end


function _M.append_child(self, span)
    table.insert(self.children, span)
end


function _M.set_status(self, code, message)
    code = span_status.validate(code)
    local status = {
        code = code,
        message = ""
    }
    if code == span_status.ERROR then
        status.message = message
    end

    self.status = status
end


function _M.set_attributes(self, ...)
    for _, attr in ipairs({ ... }) do
        table.insert(self.attributes, attr)
    end
end


function _M.finish(self)
    self.end_time = util.time_nano()
end

function _M.release(self)
    self.name = nil
    self.start_time = nil
    self.end_time = nil
    self.kind = nil
    self.status = nil
    if self.attributes then
        for i = #self.attributes, 1, -1 do
            self.attributes[i] = nil
        end
    end

    if self.children then
        for i = #self.children, 1, -1 do
            self.children[i] = nil
        end
    end

    tablepool.release(pool_name, self)
end

return _M
