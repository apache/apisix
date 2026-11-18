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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # Mock upstream: records the exact bytes of each request body, answers as
    # OpenAI (an SSE stream when the request asks for one).
    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai_key_order;
            listen 7761;

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data()
                    ngx.shared["test"]:set("received", raw)
                    if raw:find('"stream":true', 1, true) then
                        ngx.header["Content-Type"] = "text/event-stream"
                        ngx.print('data: {"id":"c","object":"chat.completion.chunk","choices":'
                                  .. '[{"index":0,"delta":{"content":"ok"},"finish_reason":"stop"}]}\\n\\n'
                                  .. 'data: [DONE]\\n\\n')
                        return
                    end
                    ngx.header["Content-Type"] = "application/json"
                    ngx.print('{"id":"c","object":"chat.completion","choices":[{"index":0,"message":'
                              .. '{"role":"assistant","content":"ok"},"finish_reason":"stop"}],'
                              .. '"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}')
                }
            }

            location /received {
                content_by_lua_block {
                    ngx.print(ngx.shared["test"]:get("received") or "")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});


run_tests();

__DATA__

=== TEST 1: set routes: options.model reshapes the body, none leaves it untouched
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local route = [[{
                "uri": "%s",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": {"header": {"Authorization": "Bearer token"}},
                        %s
                        "override": {"endpoint": "http://localhost:7761/v1/chat/completions"},
                        "ssl_verify": false
                    }
                }
            }]]
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 string.format(route, "/reshaped", '"options": {"model": "gpt-4o"},'))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT, string.format(route, "/untouched", ""))
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: a reshaped body keeps the client's key order
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local client_body = '{"model":"client-model","messages":[{"role":"user","content":"hi"}],'
                .. '"response_format":{"type":"json_schema","json_schema":{"name":"probe","schema":'
                .. '{"type":"object","properties":{"zeta":{"type":"string"},"alpha":{"type":"string"},'
                .. '"mid":{"type":"integer"}},"required":["zeta","alpha","mid"]}}},"stop":[]}'
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/reshaped", {
                method = "POST", body = client_body, headers = {["Content-Type"] = "application/json"},
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            local received = httpc:request_uri("http://127.0.0.1:7761/received").body
            -- Only the value options.model replaced differs from what the client sent.
            ngx.say(res.status)
            ngx.say(received == client_body:gsub('"client%-model"', '"gpt-4o"') and "same order" or received)
        }
    }
--- response_body
200
same order



=== TEST 3: keys APISIX adds (stream_options) follow the client's, in order
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local client_body = '{"stream":true,"model":"m","messages":[{"role":"user","content":"hi"}]}'
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/reshaped", {
                method = "POST", body = client_body, headers = {["Content-Type"] = "application/json"},
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.say(res.status)
            ngx.say(httpc:request_uri("http://127.0.0.1:7761/received").body)
        }
    }
--- response_body
200
{"stream":true,"model":"gpt-4o","messages":[{"role":"user","content":"hi"}],"stream_options":{"include_usage":true}}



=== TEST 4: an untouched body is still sent byte for byte
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local client_body = '{"model":"m", "messages":[{"role":"user","content":"hi"}],  "z":1,"a":2}'
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/untouched", {
                method = "POST", body = client_body, headers = {["Content-Type"] = "application/json"},
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.say(res.status)
            ngx.say(httpc:request_uri("http://127.0.0.1:7761/received").body == client_body)
        }
    }
--- response_body
200
true
