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
local json = require('rapidjson')
local schema_validator = json.SchemaValidator
local schema_doc = json.SchemaDocument
local json_doc = json.Document


local cached_sd = require("apisix.core.lrucache").new({count = 1000, ttl = 0})


local _M = {version = 0.2}


local function create_validator(schema)
    local sd = schema_doc(schema)
    local validator = schema_validator(sd)

    -- need to cache `validator` and `sd` object at same time
    return {validator, sd}
end


-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check(schema, json)
    local validator = cached_sd(schema, nil, create_validator, schema)[1]

    local d = json_doc(json)
    return validator:validate(d)
end


return _M
