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
local host_pattern = [[^http(s)?:\/\/([a-zA-Z0-9-_.]+:.+\@)?[a-zA-Z0-9-_.:]+$]]
local prefix_pattern = [[^[\/a-zA-Z0-9-_.]+$]]


return {
    type = 'object',
    properties = {
        host = {
            type = 'array',
            minItems = 1,
            items = {
                type = 'string',
                pattern = host_pattern,
                minLength = 2,
                maxLength = 100,
            },
        },
        fetch_interval = {type = 'integer', minimum = 1, default = 30},
        prefix = {
            type = 'string',
            pattern = prefix_pattern,
            maxLength = 100,
            default = '/nacos/v1/'
        },
        weight = {type = 'integer', minimum = 1, default = 100},
        timeout = {
            type = 'object',
            properties = {
                connect = {type = 'integer', minimum = 1, default = 2000},
                send = {type = 'integer', minimum = 1, default = 2000},
                read = {type = 'integer', minimum = 1, default = 5000},
            },
            default = {
                connect = 2000,
                send = 2000,
                read = 5000,
            }
        },
    },
    required = {'host'}
}
