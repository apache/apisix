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
local schema = require("apisix.plugins.ai-cache.schema")

local plugin_name = "ai-cache"

local _M = {
    version = 0.1,
    priority = 1065,
    name = plugin_name,
    schema = schema.schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.schema, conf)
    if not ok then
        return false, err
    end

    local layers = conf.layers or { "exact", "semantic" }
    for _, layer in ipairs(layers) do
        if layer == "semantic" and not (conf.semantic and conf.semantic.embedding) then
            return false, "semantic layer requires semantic.embedding to be configured"
        end
    end

    return true
end


function _M.access(conf, ctx)
    -- Phase 0 stub: will implement L1/L2 cache lookup in Phase 1
end


function _M.body_filter(conf, ctx)
    -- Phase 0 stub: will accumulate response chunks in Phase 1
end


function _M.log(conf, ctx)
    -- Phase 0 stub: will write to cache on 2xx in Phase 1
end


return _M