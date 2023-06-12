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

local host_patterns = {
    { pattern = [[^\${[_A-Za-z]([_A-Za-z0-9]*[_A-Za-z])*}$]] },
    { pattern = [[^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$]] },
}

local port_patterns = {
    { pattern = [[^\${[_A-Za-z]([_A-Za-z0-9]*[_A-Za-z])*}$]] },
    { pattern = [[^(([1-9]\d{0,3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5]))$]] },
}

local schema_schema = {
    type = "string",
    enum = { "http", "https" },
    default = "https",
}

local token_patterns = {
    { pattern = [[\${[_A-Za-z]([_A-Za-z0-9]*[_A-Za-z])*}$]] },
    { pattern = [[^[A-Za-z0-9+\/._=-]{0,4096}$]] },
}

local token_schema = {
    type = "string",
    oneOf = token_patterns,
}

local token_file_schema = {
    type = "string",
    pattern = [[^[^\:*?"<>|]*$]],
    minLength = 1,
    maxLength = 500,
}

local namespace_pattern = [[^[a-z0-9]([-a-z0-9_.]*[a-z0-9])?$]]

local namespace_regex_pattern = [[^[\x21-\x7e]*$]]

local namespace_selector_schema = {
    type = "object",
    properties = {
        equal = {
            type = "string",
            pattern = namespace_pattern,
        },
        not_equal = {
            type = "string",
            pattern = namespace_pattern,
        },
        match = {
            type = "array",
            items = {
                type = "string",
                pattern = namespace_regex_pattern
            },
            minItems = 1
        },
        not_match = {
            type = "array",
            items = {
                type = "string",
                pattern = namespace_regex_pattern
            },
            minItems = 1
        },
    },
    oneOf = {
        { required = {} },
        { required = { "equal" } },
        { required = { "not_equal" } },
        { required = { "match" } },
        { required = { "not_match" } }
    },
}

local label_selector_schema = {
    type = "string",
}

local default_weight_schema = {
    type = "integer",
    default = 50,
    minimum = 0,
}

local shared_size_schema = {
    type = "string",
    pattern = [[^[1-9][0-9]?m$]],
    default = "1m",
}

return {
    anyOf = {
        {
            type = "object",
            properties = {
                service = {
                    type = "object",
                    properties = {
                        schema = schema_schema,
                        host = {
                            type = "string",
                            oneOf = host_patterns,
                            default = "${KUBERNETES_SERVICE_HOST}",
                        },
                        port = {
                            type = "string",
                            oneOf = port_patterns,
                            default = "${KUBERNETES_SERVICE_PORT}",
                        },
                    },
                    default = {
                        schema = "https",
                        host = "${KUBERNETES_SERVICE_HOST}",
                        port = "${KUBERNETES_SERVICE_PORT}",
                    }
                },
                client = {
                    type = "object",
                    properties = {
                        token = token_schema,
                        token_file = token_file_schema,
                    },
                    default = {
                        token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
                    },
                    ["if"] = {
                        ["not"] = {
                            anyOf = {
                                { required = { "token" } },
                                { required = { "token_file" } },
                            }
                        }
                    },
                    ["then"] = {
                        properties = {
                            token_file = {
                                default = "/var/run/secrets/kubernetes.io/serviceaccount/token"
                            }
                        }
                    }
                },
                namespace_selector = namespace_selector_schema,
                label_selector = label_selector_schema,
                default_weight = default_weight_schema,
                shared_size = shared_size_schema,
            },
        },
        {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    id = {
                        type = "string",
                        pattern = [[^[a-z0-9]{1,8}$]]
                    },
                    service = {
                        type = "object",
                        properties = {
                            schema = schema_schema,
                            host = {
                                type = "string",
                                oneOf = host_patterns,
                            },
                            port = {
                                type = "string",
                                oneOf = port_patterns,
                            },
                        },
                        required = { "host", "port" }
                    },
                    client = {
                        type = "object",
                        properties = {
                            token = token_schema,
                            token_file = token_file_schema,
                        },
                        oneOf = {
                            { required = { "token" } },
                            { required = { "token_file" } },
                        },
                    },
                    namespace_selector = namespace_selector_schema,
                    label_selector = label_selector_schema,
                    default_weight = default_weight_schema,
                    shared_size = shared_size_schema,
                },
                required = { "id", "service", "client" }
            },
        }
    }
}
