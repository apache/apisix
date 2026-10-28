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

-- Schemas of the ssl-session-ticket plugin. Plain data, so that the CLI can
-- validate plugin_attr before the server starts.

local MAX_KEYS = 256

return {
    max_keys = MAX_KEYS,

    -- plugin_attr.ssl-session-ticket: the local policy of the nodes executing it
    attr = {
        type = "object",
        properties = {
            enabled = {type = "boolean", default = false},
            key_source = {
                type = "string",
                enum = {"generated", "external"},
                default = "generated",
            },
            generated = {
                type = "object",
                properties = {
                    -- seconds between two keys issuing tickets
                    rotation_interval = {
                        type = "integer",
                        minimum = 60,
                        default = 3600,
                    },
                    -- the issuing key plus the previous ones kept to decrypt
                    max_keys = {
                        type = "integer",
                        minimum = 1,
                        maximum = MAX_KEYS,
                        default = 19,
                    },
                },
                default = {
                    rotation_interval = 3600,
                    max_keys = 19,
                },
            },
        },
    },

    -- the body of PUT /apisix/admin/plugin_metadata/ssl-session-ticket
    metadata = {
        type = "object",
        properties = {
            keys = {
                description = "the complete ordered set of keys, each the base64 of 80 "
                              .. "random bytes; the first one issues tickets",
                type = "array",
                maxItems = MAX_KEYS,
                items = {type = "string"},
            },
        },
        required = {"keys"},
        additionalProperties = false,
    },
}
