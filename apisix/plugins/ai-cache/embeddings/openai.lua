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
local base = require("apisix.plugins.ai-cache.embeddings.base")

local _M = {}

_M.DEFAULT_ENDPOINT = "https://api.openai.com/v1/embeddings"

-- get_embeddings(conf, text, httpc, ssl_verify) -> (vector_table, err)
function _M.get_embeddings(conf, text, httpc, ssl_verify)
    local req = { model = conf.model, input = text }
    if conf.dimensions then
        req.dimensions = conf.dimensions
    end
    return base.fetch({
        endpoint = conf.endpoint or _M.DEFAULT_ENDPOINT,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. conf.api_key,
        },
        request = req,
        httpc = httpc,
        ssl_verify = ssl_verify,
    })
end

return _M
