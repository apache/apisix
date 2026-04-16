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


my $resp_file = 't/assets/openai-compatible-api-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);

print "Hello, World!\n";
print $resp;


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local test_type = ngx.req.get_headers()["test-type"]
                    if test_type == "options" then
                        if body.foo == "bar" then
                            ngx.status = 200
                            ngx.say("options works")
                        else
                            ngx.status = 500
                            ngx.say("model options feature doesn't work")
                        end
                        return
                    elseif test_type == "null-details" then
                        ngx.status = 200
                        ngx.say([[{
                            "id": "chatcmpl-null-test",
                            "object": "chat.completion",
                            "model": "test-model",
                            "choices": [{
                                "index": 0,
                                "message": {
                                    "role": "assistant",
                                    "content": "Hello!"
                                },
                                "finish_reason": "stop"
                            }],
                            "usage": {
                                "prompt_tokens": 10,
                                "completion_tokens": 5,
                                "total_tokens": 15,
                                "prompt_tokens_details": null,
                                "completion_tokens_details": null
                            }
                        }]])
                        return
                    elseif test_type == "null-usage" then
                        ngx.status = 200
                        ngx.say([[{
                            "id": "chatcmpl-null-usage",
                            "object": "chat.completion",
                            "model": "test-model",
                            "choices": [{
                                "index": 0,
                                "message": {
                                    "role": "assistant",
                                    "content": "Hello!"
                                },
                                "finish_reason": "stop"
                            }],
                            "usage": null
                        }]])
                        return
                    elseif test_type == "null-message" then
                        ngx.status = 200
                        ngx.say([[{
                            "id": "chatcmpl-null-msg",
                            "object": "chat.completion",
                            "model": "test-model",
                            "choices": [{
                                "index": 0,
                                "message": null,
                                "finish_reason": "stop"
                            }],
                            "usage": {
                                "prompt_tokens": 5,
                                "completion_tokens": 3,
                                "total_tokens": 8,
                                "prompt_tokens_details": null
                            }
                        }]])
                        return
                    elseif test_type == "null-function" then
                        ngx.status = 200
                        ngx.say([[{
                            "id": "chatcmpl-null-fn",
                            "object": "chat.completion",
                            "model": "test-model",
                            "choices": [{
                                "index": 0,
                                "message": {
                                    "role": "assistant",
                                    "content": null,
                                    "tool_calls": [{
                                        "id": "call_1",
                                        "type": "function",
                                        "function": null
                                    }]
                                },
                                "finish_reason": "tool_calls"
                            }],
                            "usage": {
                                "prompt_tokens": 5,
                                "completion_tokens": 3,
                                "total_tokens": 8
                            }
                        }]])
                        return
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end
                        if body.messages[1].content == "write an SQL query to get all rows from student table" then
                            ngx.print("SELECT * FROM STUDENTS")
                            return
                        end

                        ngx.status = 200
                        ngx.say([[$resp]])
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }

            location /random {
                content_by_lua_block {
                    ngx.say("path override works")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with right auth header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "anthropic",
                                    "provider": "anthropic",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "claude-sonnet-4-20250514",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 3: set route with stream = true (SSE)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "anthropic",
                                    "provider": "anthropic",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "claude-sonnet-4-20250514",
                                        "max_tokens": 512,
                                        "temperature": 1.0,
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                 }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: test is SSE works as expected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ],
                    "stream": true
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            ngx.print(#final_res .. final_res[6])
        }
    }
--- response_body_like eval
qr/6data: \[DONE\]\n\n/



=== TEST 5: set route for null usage fields test (openai-compatible provider)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "openai-compat",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "test-model"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: Anthropic conversion handles null prompt_tokens_details
Test that cjson.null (from JSON null) does not crash the converter.
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["test-type"] = "null-details",
                    },
                    body = [[{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"hi"}]}]],
                }
            )
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 200
--- response_body_like eval
qr/"input_tokens":10.*"output_tokens":5/
--- no_error_log
[error]



=== TEST 7: Anthropic conversion handles null usage object itself
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["test-type"] = "null-usage",
                    },
                    body = [[{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"hi"}]}]],
                }
            )
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 200
--- response_body_like eval
qr/"input_tokens":0.*"output_tokens":0/
--- no_error_log
[error]



=== TEST 8: Anthropic conversion handles null message and function fields
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["test-type"] = "null-message",
                    },
                    body = [[{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"test"}]}]],
                }
            )
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 200
--- response_body_like eval
qr/"type":"text"/
--- no_error_log
[error]



=== TEST 9: Anthropic conversion handles null function in tool_calls
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["test-type"] = "null-function",
                    },
                    body = [[{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"call tool"}]}]],
                }
            )
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 200
--- response_body_like eval
qr/"type":"tool_use"/
--- no_error_log
[error]
