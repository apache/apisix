#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: AI transport encodes upstream request body with sorted keys and preserves empty arrays
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local orig_http = package.loaded["resty.http"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            ngx.say(params.body)
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local body = core.json.decode([[
                {
                    "tools": [
                        {
                            "type": "function",
                            "function": {
                                "parameters": {
                                    "type": "object",
                                    "required": [],
                                    "properties": {}
                                },
                                "name": "fn"
                            }
                        }
                    ],
                    "model": "m",
                    "messages": [],
                    "empty_obj": {}
                }
            ]])

            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = body,
            }, 1000)
            if not res then
                ngx.say(err)
            end

            package.loaded["resty.http"] = orig_http
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
{"empty_obj":{},"messages":[],"model":"m","tools":[{"function":{"name":"fn","parameters":{"properties":{},"required":[],"type":"object"}},"type":"function"}]}



=== TEST 2: AI transport falls back to cjson when rapidjson encode fails
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local orig_http = package.loaded["resty.http"]
            local orig_rapidjson = package.loaded["rapidjson"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["rapidjson"] = {
                encode = function()
                    error("rapidjson failure")
                end,
                array = function(data)
                    return data
                end,
                object = function(data)
                    return data
                end,
            }

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            local decoded = core.json.decode(params.body)
                            ngx.say("model: ", decoded.model)
                            ngx.say("message role: ", decoded.messages[1].role)
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "m", messages = {{role = "user", content = "hi"}}},
            }, 1000)
            if not res then
                ngx.say(err)
            end

            package.loaded["resty.http"] = orig_http
            package.loaded["rapidjson"] = orig_rapidjson
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
model: m
message role: user
--- error_log
failed to encode AI request body with rapidjson:



=== TEST 3: cjson and rapidjson encode plain empty table fields as objects
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local rapidjson = require("rapidjson")

            local body = {
                model = "m",
                empty_table = {},
                nested = {
                    empty_table = {},
                },
            }

            local cjson_body = core.json.encode(body)
            local rapidjson_body = rapidjson.encode(body, {sort_keys = true})
            local cjson_decoded = core.json.decode(cjson_body)
            local rapidjson_decoded = core.json.decode(rapidjson_body)

            ngx.say("cjson body: ", cjson_body)
            ngx.say("rapidjson body: ", rapidjson_body)
            ngx.say("cjson empty table: ", core.json.encode(cjson_decoded.empty_table))
            ngx.say("rapidjson empty table: ", core.json.encode(rapidjson_decoded.empty_table))
            ngx.say("cjson nested empty table: ",
                    core.json.encode(cjson_decoded.nested.empty_table))
            ngx.say("rapidjson nested empty table: ",
                    core.json.encode(rapidjson_decoded.nested.empty_table))
        }
    }
--- response_body_like
\Acjson body: \{(?=.*"empty_table":\{\})(?=.*"nested":\{"empty_table":\{\}\})(?=.*"model":"m").*\}
rapidjson body: \{"empty_table":\{\},"model":"m","nested":\{"empty_table":\{\}\}\}
cjson empty table: \{\}
rapidjson empty table: \{\}
cjson nested empty table: \{\}
rapidjson nested empty table: \{\}



=== TEST 4: AI transport preserves JSON null values from cjson decode
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local orig_http = package.loaded["resty.http"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            ngx.say(params.body)
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local body = core.json.decode([[{"stop":null,"model":"m"}]])
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = body,
            }, 1000)
            if not res then
                ngx.say(err)
            end

            package.loaded["resty.http"] = orig_http
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
{"model":"m","stop":null}
--- no_error_log
failed to encode AI request body with rapidjson:



=== TEST 5: AI transport preserves manually constructed arrays
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            ngx.say(params.body)
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local body = {
                model = "m",
                messages = {
                    {role = "user", content = "hi"},
                    {role = "assistant", content = "hello"},
                },
            }
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = body,
            }, 1000)
            if not res then
                ngx.say(err)
            end

            package.loaded["resty.http"] = orig_http
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
{"messages":[{"content":"hi","role":"user"},{"content":"hello","role":"assistant"}],"model":"m"}
--- no_error_log
failed to encode AI request body with rapidjson:
