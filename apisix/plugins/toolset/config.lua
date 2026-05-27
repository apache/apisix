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
return {
    trace = {
        rate = 1, -- allow only 1 request per 100 requests
        hosts = {}, -- only the requests carrying these host headers will be traced
        paths = {}, -- only these request_uris will be traced
        gen_uid = false, -- adds a UID to the trace if none of the traceable headers are found
        vars = {}, -- add these nginx or inbuilt variables to trace table
        timespan_threshold = 0 -- requests taking longer than this value (in seconds) will be traced
    },
    table_count = {
        lua_modules = {}, -- change it
        interval = 5,
        depth = 10, -- when it is not passed, default depth will be 1
        -- optional, default is all APISIX processes
        scopes = {"worker", "privileged agent"}
    }
}
