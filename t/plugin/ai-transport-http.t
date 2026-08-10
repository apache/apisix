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
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
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
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
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
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
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
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
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



=== TEST 6: connect timeout ("Operation timed out") maps to 504
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return nil, "Operation timed out" end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "m"},
            }, 1000)
            ngx.say("err: ", err)
            ngx.say("status: ", transport.handle_error(err))

            package.loaded["resty.http"] = orig_http
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
err: connect: Operation timed out
status: 504



=== TEST 7: handle_error maps every timeout spelling to 504, others to 500
--- config
    location /t {
        content_by_lua_block {
            local transport = require("apisix.plugins.ai-transport.http")
            local cases = {
                "connect: timeout",
                "connect: connection timed out",
                "connect: operation timed out",
                "connect: Operation timed out",
                "request: connection refused",
                "request: connection reset by peer",
            }
            for _, e in ipairs(cases) do
                ngx.say(e, " => ", transport.handle_error(e))
            end
        }
    }
--- response_body
connect: timeout => 504
connect: connection timed out => 504
connect: operation timed out => 504
connect: Operation timed out => 504
request: connection refused => 500
request: connection reset by peer => 500



=== TEST 8: ngx_http_ffi_client is the default client
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    ngx.say("lua-resty-http client created")
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function() return {headers = {}, status = 200} end,
                    }
                end,
            }

            package.loaded["resty.ngx_http_ffi_client"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return 1 end,
                        request = function(_, params)
                            ngx.say("ffi client request: ", params.body)
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
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.http"] = orig_http
            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
ffi client request: {"model":"m"}
status: 200



=== TEST 9: a runtime without the C module fails the request
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    ngx.say("lua-resty-http client created")
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function() return {headers = {}, status = 200} end,
                    }
                end,
            }

            -- the Lua half loads even when the C module is not built in
            package.loaded["resty.ngx_http_ffi_client"] = {
                new = function()
                    return nil, "ngx_http_ffi_client_module is not loaded"
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            for _ = 1, 2 do
                local res, err = transport.request({
                    host = "127.0.0.1",
                    port = 80,
                    path = "/",
                    body = {model = "m"},
                }, 1000)
                ngx.say("status: ", res and res.status or err)
            end

            package.loaded["resty.http"] = orig_http
            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
status: failed to create http client: ngx_http_ffi_client_module is not loaded
status: failed to create http client: ngx_http_ffi_client_module is not loaded



=== TEST 10: plugin_attr.ai-proxy.http_client selects lua-resty-http
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            ngx.say("lua-resty-http request: ", params.body)
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["resty.ngx_http_ffi_client"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return 1 end,
                        request = function()
                            ngx.say("ffi client request")
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
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.http"] = orig_http
            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
lua-resty-http request: {"model":"m"}
status: 200



=== TEST 11: the lua-resty-http path reaches a real upstream
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
--- config
    location = /mock-llm {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.header["Content-Type"] = "application/json"
            ngx.print('{"echo":', ngx.req.get_body_data(), '}')
        }
    }

    location /t {
        content_by_lua_block {
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]

            -- lua-resty-http stays real; only the client that must not be
            -- picked is stubbed, so a regression in the selection shows up
            package.loaded["resty.ngx_http_ffi_client"] = {
                new = function()
                    ngx.log(ngx.ERR, "unexpected ngx_http_ffi_client selection")
                    return nil, "unexpected ngx_http_ffi_client selection"
                end,
            }

            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                method = "POST",
                scheme = "http",
                host = "127.0.0.1",
                port = 1984,
                path = "/mock-llm",
                headers = {["content-type"] = "application/json"},
                body = {model = "m"},
            }, 2000)

            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi

            if not res then
                ngx.say("err: ", err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-type: ", res.headers["Content-Type"])
            ngx.say("body: ", res:read_body())
            transport.set_keepalive(res, 60000, 30)
        }
    }
--- response_body
status: 200
content-type: application/json
body: {"echo":{"model":"m"}}
--- no_error_log
[error]
unexpected ngx_http_ffi_client selection



=== TEST 12: a module that loads but is not a table fails the request
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    ngx.say("lua-resty-http client created")
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function() return {headers = {}, status = 200} end,
                    }
                end,
            }

            -- require() returns this instead of the module table
            package.loaded["resty.ngx_http_ffi_client"] = "not a module"

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.http"] = orig_http
            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
status: failed to create http client: resty.ngx_http_ffi_client is not available: not a module
--- error_log
resty.ngx_http_ffi_client is not available: not a module



=== TEST 13: an unknown plugin_attr.ai-proxy.http_client fails the request
--- extra_yaml_config
plugin_attr:
    ai-proxy:
        http_client: curl
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    ngx.say("lua-resty-http client created")
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function() return {headers = {}, status = 200} end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.http"] = orig_http
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
status: failed to create http client: invalid plugin_attr.ai-proxy: property "http_client" validation failed: matches none of the enum values
--- error_log
invalid plugin_attr.ai-proxy: property "http_client" validation failed



=== TEST 14: the C client resolves a hostname through the gateway's resolver
--- config
    location /t {
        content_by_lua_block {
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            -- the C client dials on its own, so the transport has to hand it an
            -- address; the name has to survive in the Host header
            package.loaded["resty.ngx_http_ffi_client"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function(_, params)
                            ngx.say("connect host: ", params.host)
                            ngx.say("ssl_server_name: ", params.ssl_server_name)
                            return 1
                        end,
                        request = function(_, params)
                            ngx.say("Host header: ", params.headers["Host"])
                            return {headers = {}, status = 200}
                        end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                scheme = "http",
                host = "localhost",
                port = 1980,
                path = "/v1/chat/completions",
                headers = {["content-type"] = "application/json"},
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
connect host: 127.0.0.1
ssl_server_name: localhost
Host header: localhost:1980
status: 200
--- no_error_log
[error]



=== TEST 15: a module whose loader raises fails the request
--- config
    location /t {
        content_by_lua_block {
            local orig_http = package.loaded["resty.http"]
            local orig_ffi = package.loaded["resty.ngx_http_ffi_client"]
            local orig_preload = package.preload["resty.ngx_http_ffi_client"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]

            package.loaded["resty.http"] = {
                new = function()
                    ngx.say("lua-resty-http client created")
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function() return {headers = {}, status = 200} end,
                    }
                end,
            }

            -- an unloaded module whose loader raises: this is what a require()
            -- failure looks like, as opposed to one that loads the wrong thing
            package.loaded["resty.ngx_http_ffi_client"] = nil
            package.preload["resty.ngx_http_ffi_client"] = function()
                error("simulated loader failure", 0)
            end

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "m"},
            }, 1000)
            ngx.say("status: ", res and res.status or err)

            package.loaded["resty.http"] = orig_http
            package.loaded["resty.ngx_http_ffi_client"] = orig_ffi
            package.preload["resty.ngx_http_ffi_client"] = orig_preload
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
        }
    }
--- response_body
status: failed to create http client: resty.ngx_http_ffi_client is not available: simulated loader failure
--- error_log
resty.ngx_http_ffi_client is not available: simulated loader failure



=== TEST 16: the C client carries a buffered request to a real upstream
--- skip_eval: 3: system((($ENV{TEST_NGINX_BINARY} || "nginx") . " -V 2>&1 | grep -q ngx_http_ffi_client")) != 0
--- config
    location = /mock-buffered {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.header["Content-Type"] = "application/json"
            ngx.print('{"echo":', ngx.req.get_body_data(), '}')
        }
    }

    location /t {
        content_by_lua_block {
            -- nothing stubbed: this is the real C client on the default setting
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                method = "POST",
                scheme = "http",
                host = "127.0.0.1",
                port = 1984,
                path = "/mock-buffered",
                headers = {["content-type"] = "application/json"},
                body = {model = "m"},
            }, 2000)
            if not res then
                ngx.say("err: ", err)
                return
            end
            ngx.say("status: ", res.status)
            ngx.say("content-type: ", res.headers["Content-Type"])
            ngx.say("body: ", res:read_body())
            transport.set_keepalive(res, 60000, 30)
        }
    }
--- response_body
status: 200
content-type: application/json
body: {"echo":{"model":"m"}}
--- no_error_log
[error]



=== TEST 17: the C client streams an SSE response through body_reader
--- skip_eval: 3: system((($ENV{TEST_NGINX_BINARY} || "nginx") . " -V 2>&1 | grep -q ngx_http_ffi_client")) != 0
--- config
    location = /mock-sse {
        content_by_lua_block {
            ngx.header["Content-Type"] = "text/event-stream"
            for i = 1, 3 do
                ngx.print("data: {\"n\":", i, "}\n\n")
                ngx.flush(true)
            end
            ngx.print("data: [DONE]\n\n")
            ngx.flush(true)
        }
    }

    location /t {
        content_by_lua_block {
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                method = "POST",
                scheme = "http",
                host = "127.0.0.1",
                port = 1984,
                path = "/mock-sse",
                headers = {["content-type"] = "application/json"},
                body = {model = "m", stream = true},
            }, 2000)
            if not res then
                ngx.say("err: ", err)
                return
            end
            ngx.say("status: ", res.status)
            ngx.say("content-type: ", res.headers["Content-Type"])

            local reader = res.body_reader
            if not reader then
                ngx.say("no body_reader")
                return
            end
            local buf = {}
            while true do
                local chunk, rerr = reader(4096)
                if rerr then
                    ngx.say("read err: ", rerr)
                    break
                end
                if not chunk then
                    break
                end
                buf[#buf + 1] = chunk
            end
            local body = table.concat(buf)
            local n = select(2, body:gsub("data: ", ""))
            ngx.say("sse events: ", n)
            ngx.say("saw done: ", body:find("[DONE]", 1, true) ~= nil)
        }
    }
--- response_body
status: 200
content-type: text/event-stream
sse events: 4
saw done: true
--- no_error_log
[error]



=== TEST 18: the C client reuses a pooled connection across requests
--- skip_eval: 3: system((($ENV{TEST_NGINX_BINARY} || "nginx") . " -V 2>&1 | grep -q ngx_http_ffi_client")) != 0
--- config
    location = /mock-keepalive {
        # counts requests served on this connection: 1,2,3 proves one
        # pooled connection carried all three
        content_by_lua_block { ngx.print("req ", ngx.var.connection_requests) }
    }

    location /t {
        content_by_lua_block {
            local transport = require("apisix.plugins.ai-transport.http")
            for i = 1, 3 do
                local res, err = transport.request({
                    method = "POST",
                    scheme = "http",
                    host = "127.0.0.1",
                    port = 1984,
                    path = "/mock-keepalive",
                    headers = {["content-type"] = "application/json"},
                    body = {model = "m"},
                }, 2000)
                if not res then
                    ngx.say(i, ": err ", err)
                    return
                end
                local body = res:read_body()
                transport.set_keepalive(res, 60000, 30)
                ngx.say(i, ": ", res.status, " ", body)
            end
        }
    }
--- response_body
1: 200 req 1
2: 200 req 2
3: 200 req 3
--- no_error_log
[error]



=== TEST 19: the C client reaches an upstream named by hostname
--- skip_eval: 3: system((($ENV{TEST_NGINX_BINARY} || "nginx") . " -V 2>&1 | grep -q ngx_http_ffi_client")) != 0
--- config
    location = /mock-host {
        content_by_lua_block {
            ngx.print("host header: ", ngx.var.http_host)
        }
    }

    location /t {
        content_by_lua_block {
            -- "localhost" only resolves through core.resolver, so this drives
            -- resolve_upstream_host with the real client behind it
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                method = "POST",
                scheme = "http",
                host = "localhost",
                port = 1984,
                path = "/mock-host",
                headers = {["content-type"] = "application/json"},
                body = {model = "m"},
            }, 2000)
            if not res then
                ngx.say("err: ", err)
                return
            end
            ngx.say("status: ", res.status)
            ngx.say(res:read_body())
        }
    }
--- response_body
status: 200
host header: localhost:1984
--- no_error_log
[error]



=== TEST 20: the C client verifies TLS against the configured trust store
--- skip_eval: 3: system((($ENV{TEST_NGINX_BINARY} || "nginx") . " -V 2>&1 | grep -q ngx_http_ffi_client")) != 0
--- http_config
    server {
        listen 21981 ssl;
        ssl_certificate     cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;
        server_name test.com;
        location = /mock-tls {
            content_by_lua_block { ngx.print("tls ok") }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            -- no per-call CA: the trust store comes from
            -- lua_ssl_trusted_certificate, as it does for every cosocket
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                method = "POST",
                scheme = "https",
                host = "127.0.0.1",
                port = 21981,
                path = "/mock-tls",
                ssl_verify = true,
                ssl_server_name = "test.com",
                headers = {["content-type"] = "application/json"},
                body = {model = "m"},
            }, 2000)
            if not res then
                ngx.say("err: ", err)
                return
            end
            ngx.say("status: ", res.status)
            ngx.say(res:read_body())
        }
    }
--- response_body
status: 200
tls ok
--- no_error_log
[error]
