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

local host_pattern = [[^([a-zA-Z0-9-_.]+:.+\@)?[a-zA-Z0-9-_.:]+$]]

return {
    type = 'object',
    properties = {
        db_conf = {
            type = 'object',
            properties = {
                host = { type = 'string', minLength = 1, maxLength = 500, pattern = host_pattern },
                port = { type = 'integer', minimum = 1, maximum = 65535, default = 3306 },
                database = { type = 'string', minLength = 1, maxLength = 64 },
                user = { type = 'string', minLength = 1, maxLength = 64 },
                password = { type = 'string', minLength = 1, maxLength = 64 },
            },
            required = { 'host', 'database', 'user', 'password' }
        },
        full_fetch_interval = {
            type = 'integer', minimum = 90, maximum = 3600, default = 300,
        },
        incremental_fetch_interval = {
            type = 'integer', minimum = 5, maximum = 60, default = 15,
        },
        default_weight = {
            type = 'integer', minimum = 0, maximum = 100, default = 100,
        },
    },
    required = { 'db_conf' }
}
