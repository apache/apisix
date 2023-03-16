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
    type = "object",
    properties = {
        servers = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
            }
        },
        fetch_interval = {type = "integer", minimum = 1, default = 3},
        keepalive = {
            type = "boolean",
            default = true
        },
        weight = {type = "integer", minimum = 1, default = 1},
        timeout = {
            type = "object",
            properties = {
                connect = {type = "integer", minimum = 1, default = 2000},
                read = {type = "integer", minimum = 1, default = 2000},
                wait = {type = "integer", minimum = 1, default = 60}
            },
            default = {
                connect = 2000,
                read = 2000,
                wait = 60,
            }
        },
        skip_services = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
            }
        },
        dump = {
            type = "object",
            properties = {
                path = {type = "string", minLength = 1},
                load_on_init = {type = "boolean", default = true},
                expire = {type = "integer", default = 0},
            },
            required = {"path"},
        },
        default_service = {
            type = "object",
            properties = {
                host = {type = "string"},
                port = {type = "integer"},
                metadata = {
                    type = "object",
                    properties = {
                        fail_timeout = {type = "integer", default = 1},
                        weight = {type = "integer", default = 1},
                        max_fails = {type = "integer", default = 1}
                    },
                    default = {
                        fail_timeout = 1,
                        weight = 1,
                        max_fails = 1
                    }
                }
            }
        }
    },

    required = {"servers"}
}

