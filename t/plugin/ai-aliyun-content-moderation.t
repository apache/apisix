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

BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

use t::APISIX 'no_plan';

log_level("debug");
repeat_each(1);
no_long_string();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6724;

            default_type 'application/json';

            location / {
                content_by_lua_block {
                    local core = require("apisix.core")
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    if not body then
                        ngx.status(400)
                        return
                    end

                    local fixture_loader = require("lib.fixture_loader")
                    local fixture_name = "aliyun/moderation-safe.json"
                    if core.string.find(body, "kill") then
                        fixture_name = "aliyun/moderation-risk.json"
                    end
                    local content, load_err = fixture_loader.load(fixture_name)
                    if not content then
                        ngx.status = 500
                        ngx.say(load_err)
                        return
                    end
                    ngx.status = 200
                    ngx.print(content)
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugin_attr:
    prometheus:
        refresh_interval: 0.1
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: create a route with ai-aliyun-content-moderation plugin only
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "fail_mode": "error"
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



=== TEST 2: fail_mode=error without ai-proxy/ai-proxy-multi should fail
--- request
POST /chat
{"prompt": "What is 1+1?"}
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 500
--- response_body_chomp
no ai instance picked, ai-aliyun-content-moderation plugin must be used with ai-proxy or ai-proxy-multi plugin



=== TEST 3: check prompt in request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 4: non-violent prompt should succeed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 5: violent prompt should failed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/As an AI language model, I cannot write unethical or controversial content for you./



=== TEST 6: check ai response (stream=false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, provider in ipairs({"openai", "deepseek", "openai-compatible"}) do
                local code, body = t('/apisix/admin/routes/' .. provider,
                    ngx.HTTP_PUT,
                    string.format([[{
                        "uri": "/chat-%s",
                        "plugins": {
                          "ai-proxy": {
                              "provider": "%s",
                              "auth": {
                                  "header": {
                                      "Authorization": "Bearer wrongtoken"
                                  }
                              },
                              "override": {
                                  "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                              }
                          },
                          "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": true,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected"
                          }
                        }
                    }]], provider, provider)
                )
                if code >= 300 then
                    ngx.status = code
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: violent response should failed for openai provider
--- request
POST /chat-openai
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 8: violent response should failed for deepseek provider
--- request
POST /chat-deepseek
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 9: violent response should failed for openai-compatible provider
--- request
POST /chat-openai-compatible
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 10: check ai request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, provider in ipairs({"openai", "deepseek", "openai-compatible"}) do
                local code, body = t('/apisix/admin/routes/' .. provider,
                    ngx.HTTP_PUT,
                    string.format([[{
                        "uri": "/chat-%s",
                        "plugins": {
                          "ai-proxy": {
                              "provider": "%s",
                              "auth": {
                                  "header": {
                                      "Authorization": "Bearer wrongtoken"
                                  }
                              },
                              "override": {
                                  "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                              }
                          },
                          "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": true,
                            "check_response": false,
                            "deny_code": 400,
                            "deny_message": "your request is rejected"
                          }
                        }
                    }]], provider, provider)
                )
                if code >= 300 then
                    ngx.status = code
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 11: violent response should failed for openai provider
--- request
POST /chat-openai
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 12: violent response should failed for deepseek provider
--- request
POST /chat-deepseek
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 13: violent response should failed for openai-compatible provider
--- request
POST /chat-openai-compatible
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 14: content moderation should keep usage data in response
--- request
POST /chat-openai
{"messages":[{"role":"user","content":"I want to kill you"}]}
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/completion_tokens/



=== TEST 15: content moderation should keep real llm model in response
--- request
POST /chat-openai
{"model": "gpt-3.5-turbo","messages":[{"role":"user","content":"I want to kill you"}]}
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/gpt-3.5-turbo/



=== TEST 16: set route with stream = true (SSE) and stream_mode = final_packet
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
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
                                        "max_tokens": 512,
                                        "temperature": 1.0,
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions?offensive=true"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected"
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



=== TEST 17: test is SSE works as expected when response is offensive
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
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                core.log.warn("CHUNK IS ", inspect(chunk))
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end
            ngx.print(final_res[5])
        }
    }
--- response_body_like eval
qr/"risk_level":"high"/



=== TEST 18: set route with stream = true (SSE) and stream_mode = realtime
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
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
                                        "max_tokens": 512,
                                        "temperature": 1.0,
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions?offensive=true"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 5
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



=== TEST 19: test is SSE works as expected when third response chunk is offensive and stream_mode = realtime
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
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                core.log.warn("CHUNK IS ", inspect(chunk))
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end
            ngx.print(final_res[3])
        }
    }
--- response_body_like eval
qr/your request is rejected/
--- grep_error_log eval
qr/execute content moderation/
--- grep_error_log_out
execute content moderation
execute content moderation



=== TEST 20: set route with stream = true (SSE) and stream_mode = realtime with larger buffer and large timeout
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
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
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
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 30000,
                            "stream_check_interval": 30
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



=== TEST 21: test is SSE works, stream_mode = realtime, large buffer + large timeout but content moderation should be called once
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
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                core.log.warn("CHUNK IS ", inspect(chunk))
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
qr/6data:/
--- grep_error_log eval
qr/execute content moderation/
--- grep_error_log_out
execute content moderation



=== TEST 22: set route with stream = true (SSE) and stream_mode = realtime with small buffer
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
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
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
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 1,
                            "stream_check_interval": 3
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



=== TEST 23: test is SSE works, stream_mode = realtime, small buffer. content moderation will be called on each chunk
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
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                core.log.warn("CHUNK IS ", inspect(chunk))
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
qr/6data:/
--- grep_error_log eval
qr/execute content moderation/
--- grep_error_log_out
execute content moderation
execute content moderation
execute content moderation



=== TEST 24: set route with stream = true (SSE) and stream_mode = realtime with large buffer but small timeout
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
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
                                        "max_tokens": 512,
                                        "temperature": 1.0,
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions?delay=true"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 10000,
                            "stream_check_interval": 0.1
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



=== TEST 25: test is SSE works, stream_mode = realtime, large buffer + small timeout: content moderation will be called on each chunke
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
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                core.log.warn("CHUNK IS ", inspect(chunk))
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
qr/6data:/
--- grep_error_log eval
qr/execute content moderation/
--- grep_error_log_out
execute content moderation
execute content moderation
execute content moderation



=== TEST 26: set route with check_response enabled for usage preservation test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/openai',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-openai",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": false,
                        "check_response": true,
                        "deny_code": 400,
                        "deny_message": "your request is rejected"
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



=== TEST 27: response deny should preserve actual LLM usage (not zeros)
--- request
POST /chat-openai
{"messages":[{"role":"user","content":"I want to kill you"}]}
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/"completion_tokens"\s*:\s*5.*"prompt_tokens"\s*:\s*8|"prompt_tokens"\s*:\s*8.*"completion_tokens"\s*:\s*5/s



=== TEST 28: set route for empty content and multimodal tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 29: request with empty string content should pass through without moderation error
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 30: multimodal request with image-only content should pass through
--- request
POST /chat
{ "messages": [ { "role": "user", "content": [ { "type": "image_url", "image_url": { "url": "data:image/jpg;base64,abc" } } ] } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 31: multimodal request with text+image content should moderate text
--- request
POST /chat
{ "messages": [ { "role": "user", "content": [ { "type": "text", "text": "I want to kill you" }, { "type": "image_url", "image_url": { "url": "data:image/jpg;base64,abc" } } ] } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 32: multimodal request with safe text and image should pass through
--- request
POST /chat
{ "messages": [ { "role": "user", "content": [ { "type": "text", "text": "What is 1+1?" }, { "type": "image_url", "image_url": { "url": "data:image/jpg;base64,abc" } } ] } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 33: messages with tool role should pass through
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "hello" }, { "role": "assistant", "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "get_weather"}}] }, { "role": "tool", "tool_call_id": "call_1", "content": "sunny" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 34: skip response moderation when upstream returns error status
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aliyun-content-moderation")
            local ctx = {
                picked_ai_instance = { provider = "openai" },
                var = { request_type = "ai_stream" },
                llm_response_contents_in_chunk = nil,
            }
            local conf = {
                endpoint = "https://fake.aliyun.com",
                region_id = "cn-test",
                access_key_id = "id",
                access_key_secret = "secret",
                check_response = true,
                stream_check_mode = "realtime",
                stream_check_cache_size = 128,
                stream_check_interval = 3,
            }
            ngx.status = 400
            local ok, msg = plugin.lua_body_filter(conf, ctx, {}, "body")
            ngx.status = 200
            ngx.say("ok:", ok or "nil", ", msg:", msg or "nil")
        }
    }
--- request
GET /t
--- response_body
ok:nil, msg:nil
--- error_log
skip response check because upstream returned error status: 400



=== TEST 35: llm_active_connections gauge is 0 after response denied by content moderation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- create route with prometheus + ai-proxy + content moderation (check_response=true)
            local code, body = t('/apisix/admin/routes/gauge-test',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-gauge-test",
                    "plugins": {
                        "prometheus": {},
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- create metrics route
            local code, body = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/apisix/prometheus/metrics",
                    "plugins": { "public-api": {} }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")
            local httpc = http.new()

            -- send a chat request that will be denied by content moderation
            -- (LLM mock always returns "I will kill you." which triggers denial)
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/chat-gauge-test",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "aliyun/chat-with-harmful.json",
                    },
                    body = [[{"messages":[{"role":"user","content":"What is 1+1?"}]}]],
                }
            )
            if not res then
                ngx.say("failed to send chat request: " .. (err or "unknown"))
                return
            end
            -- expect 400 from content moderation denial
            if res.status ~= 400 then
                ngx.say("expected 400, got " .. res.status)
                return
            end

            -- wait for prometheus metrics cache to refresh
            ngx.sleep(1)

            -- fetch prometheus metrics
            local metric_resp, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            )
            if not metric_resp then
                ngx.say("failed to fetch metrics: " .. (err or "unknown"))
                return
            end

            local has_zero = metric_resp.body:match([[apisix_llm_active_connections%b{}%s+0%.?0*]])
            local has_non_zero = metric_resp.body:match([[apisix_llm_active_connections%b{}%s+[1-9]%d*%.?%d*]])

            if has_zero and not has_non_zero then
                ngx.say("passed")
            else
                ngx.say("apisix_llm_active_connections has non-zero sample or missing zero sample:\n"
                    .. metric_resp.body)
            end
        }
    }
--- response_body
passed



=== TEST 36: llm_active_connections gauge is 0 after response denied by content moderation (ai-proxy-multi)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- create route with prometheus + ai-proxy-multi + content moderation (check_response=true)
            local code, body = t('/apisix/admin/routes/gauge-test-multi',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-gauge-test-multi",
                    "plugins": {
                        "prometheus": {},
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "openai-inst",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer wrongtoken"
                                        }
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                                    }
                                }
                            ]
                        },
                        "ai-aliyun-content-moderation": {
                            "endpoint": "http://localhost:6724",
                            "region_id": "cn-shanghai",
                            "access_key_id": "fake-key-id",
                            "access_key_secret": "fake-key-secret",
                            "risk_level_bar": "high",
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400,
                            "deny_message": "your request is rejected"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- create metrics route
            local code, body = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/apisix/prometheus/metrics",
                    "plugins": { "public-api": {} }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")
            local httpc = http.new()

            -- send a chat request that will be denied by content moderation
            -- (LLM mock always returns "I will kill you." which triggers denial)
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/chat-gauge-test-multi",
                {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "aliyun/chat-with-harmful.json",
                    },
                    body = [[{"messages":[{"role":"user","content":"What is 1+1?"}]}]],
                }
            )
            if not res then
                ngx.say("failed to send chat request: " .. (err or "unknown"))
                return
            end
            -- expect 400 from content moderation denial
            if res.status ~= 400 then
                ngx.say("expected 400, got " .. res.status)
                return
            end

            -- wait for prometheus metrics cache to refresh
            ngx.sleep(1)

            -- fetch prometheus metrics
            local metric_resp, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            )
            if not metric_resp then
                ngx.say("failed to fetch metrics: " .. (err or "unknown"))
                return
            end

            local has_zero = metric_resp.body:match([[apisix_llm_active_connections%b{}%s+0%.?0*]])
            local has_non_zero = metric_resp.body:match([[apisix_llm_active_connections%b{}%s+[1-9]%d*%.?%d*]])

            if has_zero and not has_non_zero then
                ngx.say("passed")
            else
                ngx.say("apisix_llm_active_connections has non-zero sample or missing zero sample:\n"
                    .. metric_resp.body)
            end
        }
    }
--- response_body
passed



=== TEST 37: set route for Responses API content moderation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/chat", "/v1/responses"],
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 38: Responses API violent input should be blocked by content moderation
--- request
POST /v1/responses
{ "input": "I want to kill you", "model": "gpt-4o" }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/As an AI language model, I cannot write unethical or controversial content for you./



=== TEST 39: Responses API deny response should use Responses API format (non-streaming)
--- request
POST /v1/responses
{ "input": "I want to kill you", "model": "gpt-4o" }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/(?=.*"object"\s*:\s*"response")(?=.*"output_text")(?=.*"input_tokens")/s



=== TEST 40: set route for Responses API streaming content moderation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/chat", "/v1/responses"],
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 41: Responses API streaming deny response should use SSE Responses API format
--- request
POST /v1/responses
{ "input": "I want to kill you", "model": "gpt-4o", "stream": true }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/event: response\.output_text\.delta\ndata:.*"delta".*\n\nevent: response\.completed\ndata:.*"object"\s*:\s*"response"/s



=== TEST 42: Responses API deny response should contain input_tokens (not prompt_tokens) in usage
--- request
POST /v1/responses
{ "input": "I want to kill you", "model": "gpt-4o" }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/(?=.*"input_tokens"\s*:\s*0)(?=.*"output_tokens"\s*:\s*0)/s
--- response_body_unlike eval
qr/"prompt_tokens"/



=== TEST 43: set route with deepseek provider for Responses API nil-schema fix
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/chat", "/v1/responses"],
                    "plugins": {
                      "ai-proxy": {
                          "provider": "deepseek",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer wrongtoken"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 44: Responses API request with non-openai provider (deepseek) should not panic from nil schema check
--- request
POST /v1/responses
{ "input": "safe prompt", "model": "deepseek-chat" }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 400



=== TEST 45: route without ai-proxy, default fail_mode (skip)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/plain",
                    "plugins": {
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
                      }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6724": 1
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



=== TEST 46: plain HTTP request passes through by default (skip) and is logged
--- request
POST /plain
name=alice&action=upload
--- more_headers
Content-Type: multipart/form-data
--- error_code: 200
--- error_log
ai-aliyun-content-moderation skipped



=== TEST 47: create route for request_check_mode tests (default mode = last)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-last",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true
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



=== TEST 48: default mode (last) - harmful earlier user turn is skipped
--- request
POST /chat-last
{ "messages": [ { "role": "user", "content": "I want to kill you" }, { "role": "assistant", "content": "ok" }, { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 49: default mode (last) - harmful last user turn is detected
--- request
POST /chat-last
{ "messages": [ { "role": "user", "content": "What is 1+1?" }, { "role": "assistant", "content": "ok" }, { "role": "user", "content": "I want to kill you" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 50: role-aware - non-user (assistant) last message, no user turn to check, request passes
--- request
POST /chat-last
{ "messages": [ { "role": "user", "content": "What is 1+1?" }, { "role": "assistant", "content": "I want to kill you" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 51: create route with request_check_mode "all"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-all",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "request_check_mode": "all"
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



=== TEST 52: request_check_mode "all" - harmful earlier user turn is detected
--- request
POST /chat-all
{ "messages": [ { "role": "user", "content": "I want to kill you" }, { "role": "assistant", "content": "ok" }, { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 53: request_check_mode "all" stays role-aware - harmful system message is skipped
--- request
POST /chat-all
{ "messages": [ { "role": "system", "content": "I want to kill you" }, { "role": "user", "content": "hi" }, { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 54: create route with small request_check_length_limit (exercises multi-chunk path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-chunk",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "request_check_length_limit": 10
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



=== TEST 55: multi-chunk - harmful content in a later chunk after multibyte chars is detected
--- request
POST /chat-chunk
{ "messages": [ { "role": "user", "content": "这是一段安全的中文内容 kill" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 56: request_check_length_limit must be >= 1 (guards against infinite loop)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-bad",
                    "plugins": {
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "request_check_length_limit": 0
                      }
                    }
                }]]
            )
            ngx.say(code >= 300 and "rejected" or "accepted")
        }
    }
--- response_body
rejected



=== TEST 57: extract_turn_content - last mode uses the trailing user/tool block
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.ai-protocols.openai-chat")
            local body = {
                messages = {
                    { role = "system", content = "sys" },
                    { role = "user", content = "u1" },
                    { role = "assistant", tool_calls = {} },
                    { role = "tool", content = "t1" },
                    { role = "tool", content = "t2" },
                }
            }
            local roles = { user = true, tool = true }
            ngx.say("last:", table.concat(proto.extract_turn_content(body, "last", roles), ","))
            ngx.say("all:", table.concat(proto.extract_turn_content(body, "all", roles), ","))
            ngx.say("user_only_last_count:",
                    #proto.extract_turn_content(body, "last", { user = true }))
            ngx.say("system:", table.concat(proto.extract_system_content(body), ","))
        }
    }
--- response_body
last:t1,t2
all:u1,t1,t2
user_only_last_count:0
system:sys



=== TEST 58: extract_turn_content - a fresh user turn skips harmful history
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.ai-protocols.openai-chat")
            local body = {
                messages = {
                    { role = "user", content = "old kill" },
                    { role = "assistant", content = "ok" },
                    { role = "user", content = "new safe" },
                }
            }
            local roles = { user = true, tool = true }
            ngx.say("last:", table.concat(proto.extract_turn_content(body, "last", roles), ","))
        }
    }
--- response_body
last:new safe



=== TEST 59: create route with request_check_roles user/tool/system
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-roles",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "request_check_roles": ["user", "tool", "system"]
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



=== TEST 60: tool content in the latest turn is moderated and blocked
--- request
POST /chat-roles
{ "messages": [ { "role": "system", "content": "safe" }, { "role": "user", "content": "hello" }, { "role": "assistant", "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "f"}}] }, { "role": "tool", "tool_call_id": "c1", "content": "please kill" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 61: harmful tool not in the latest turn is skipped (last mode)
--- request
POST /chat-roles
{ "messages": [ { "role": "user", "content": "hello" }, { "role": "assistant", "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "f"}}] }, { "role": "tool", "tool_call_id": "c1", "content": "kill" }, { "role": "assistant", "content": "ok" }, { "role": "user", "content": "what is 1+1?" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 62: harmful system prompt is always moderated and blocked
--- request
POST /chat-roles
{ "messages": [ { "role": "system", "content": "please kill" }, { "role": "user", "content": "hi" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 63: repeated identical harmful system stays blocked (moderated every request)
--- request
POST /chat-roles
{ "messages": [ { "role": "system", "content": "please kill" }, { "role": "user", "content": "hi" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 64: create route with request_check_roles system only
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-sys",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "request_check_roles": ["system"]
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



=== TEST 65: with system-only roles, harmful user content is not checked
--- request
POST /chat-sys
{ "messages": [ { "role": "system", "content": "safe" }, { "role": "user", "content": "kill" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 66: with system-only roles, harmful system content is blocked
--- request
POST /chat-sys
{ "messages": [ { "role": "system", "content": "kill" }, { "role": "user", "content": "hi" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 67: create route with roles user/tool and request_check_mode all
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-tool-all",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": { "header": { "Authorization": "Bearer wrongtoken" } },
                          "override": { "endpoint": "http://127.0.0.1:1980" }
                      },
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": true,
                        "request_check_mode": "all",
                        "request_check_roles": ["user", "tool"]
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



=== TEST 68: all mode - harmful tool result in an earlier turn is detected
--- request
POST /chat-tool-all
{ "messages": [ { "role": "user", "content": "hello" }, { "role": "assistant", "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "f"}}] }, { "role": "tool", "tool_call_id": "c1", "content": "kill" }, { "role": "assistant", "content": "ok" }, { "role": "user", "content": "bye" } ] }
--- more_headers
X-AI-Fixture: aliyun/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/cannot write unethical/



=== TEST 69: invalid request_check_roles value is rejected
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/4',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-bad-role",
                    "plugins": {
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "request_check_roles": ["assistant"]
                      }
                    }
                }]]
            )
            ngx.say(code >= 300 and "rejected" or "accepted")
        }
    }
--- response_body
rejected



=== TEST 70: empty request_check_roles is rejected (minItems)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/4',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-empty-role",
                    "plugins": {
                      "ai-aliyun-content-moderation": {
                        "endpoint": "http://localhost:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "request_check_roles": []
                      }
                    }
                }]]
            )
            ngx.say(code >= 300 and "rejected" or "accepted")
        }
    }
--- response_body
rejected



=== TEST 71: openai-responses extract_turn_content / extract_system_content
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.ai-protocols.openai-responses")
            -- bare-string input is user content
            local b1 = { input = "hello user" }
            ngx.say("str_user:", table.concat(proto.extract_turn_content(b1, "last", {user=true}), ","))
            -- array input: user item, a non-turn item (boundary), then a tool output
            local b2 = { instructions = "sys instr", input = {
                { role = "user", content = "u-old" },
                { type = "reasoning", content = "r" },
                { type = "function_call_output", output = "tool-out kill" },
            }}
            ngx.say("last_ut:", table.concat(proto.extract_turn_content(b2, "last", {user=true, tool=true}), ","))
            ngx.say("last_user_only:", table.concat(proto.extract_turn_content(b2, "last", {user=true}), ","))
            ngx.say("sys:", table.concat(proto.extract_system_content(b2), ","))
            -- function_call_output.output as an array of parts
            local b3 = { input = {
                { type = "function_call_output", output = { { text = "arr-out" } } },
            }}
            ngx.say("arr_out:", table.concat(proto.extract_turn_content(b3, "all", {tool=true}), ","))
        }
    }
--- response_body
str_user:hello user
last_ut:tool-out kill
last_user_only:
sys:sys instr
arr_out:arr-out



=== TEST 72: anthropic / bedrock extract_system_content (string and block-array)
--- config
    location /t {
        content_by_lua_block {
            local anth = require("apisix.plugins.ai-protocols.anthropic-messages")
            ngx.say("anth_str:", table.concat(anth.extract_system_content({system = "anth sys"}), ","))
            ngx.say("anth_blk:", table.concat(anth.extract_system_content(
                {system = { {type="text", text="b1"}, {type="text", text="b2"} }}), ","))
            local bed = require("apisix.plugins.ai-protocols.bedrock-converse")
            ngx.say("bed_blk:", table.concat(bed.extract_system_content(
                {system = { {text="bs1"}, {text="bs2"} }}), ","))
        }
    }
--- response_body
anth_str:anth sys
anth_blk:b1,b2
bed_blk:bs1,bs2



=== TEST 73: schema check: deny_code must be within [200, 599]
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aliyun-content-moderation")
            local conf = {
                endpoint = "https://example.com",
                region_id = "cn-hangzhou",
                access_key_id = "a",
                access_key_secret = "s"
            }
            for _, code in ipairs({199, 600}) do
                conf.deny_code = code
                ngx.say(code, ": ", plugin.check_schema(conf) and "accepted" or "rejected")
            end
            conf.deny_code = 403
            ngx.say("403: ", plugin.check_schema(conf) and "accepted" or "rejected")
        }
    }
--- response_body
199: rejected
600: rejected
403: accepted
