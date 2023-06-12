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
local require = require
local core = require("apisix.core")
local pairs = pairs
local pcall = pcall


local _M = {}
local hubs = {}


function _M.store(prometheus, name)
    local ok, m = pcall(require, "apisix.stream.xrpc.protocols." .. name .. ".metrics")
    if not ok then
        core.log.notice("no metric for protocol ", name)
        return
    end

    local hub = {}
    for metric, conf in pairs(m) do
        core.log.notice("register metric ", metric, " for protocol ", name)
        hub[metric] = prometheus[conf.type](prometheus, name .. '_' .. metric,
                                            conf.help, conf.labels, conf.buckets)
    end

    hubs[name] = hub
end


function _M.load(name)
    return hubs[name]
end


return _M
