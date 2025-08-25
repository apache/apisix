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

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.status = 200
                    ngx.say([[
{
"choices": [
{
  "finish_reason": "stop",
  "index": 0,
  "message": { "content": "I will kill you.", "role": "assistant" }
}
],
"created": 1723780938,
"id": "chatcmpl-9wiSIg5LYrrpxwsr2PubSQnbtod1P",
"model": "gpt-3.5-turbo",
"object": "chat.completion",
"usage": { "completion_tokens": 5, "prompt_tokens": 8, "total_tokens": 10 }
}
                    ]])
                }
            }

            location / {
                content_by_lua_block {
                    local core = require("apisix.core")
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    if not body then
                        ngx.status(400)
                        return
                    end

                    ngx.status = 200
                    if core.string.find(body, "kill") then
                        ngx.say([[
{
  "Message": "OK",
  "Data": {
    "Advice": [
      {
        "HitLabel": "violent_incidents",
        "Answer": "As an AI language model, I cannot write unethical or controversial content for you."
      }
    ],
    "RiskLevel": "high",
    "Result": [
      {
        "RiskWords": "kill",
        "Description": "suspected extremist content",
        "Confidence": 100.0,
        "Label": "violent_incidents"
      }
    ]
  },
  "Code": 200
}
                    ]])
                    else
                        ngx.say([[
{
  "RequestId": "3262D562-1FBA-5ADF-86CB-3087603A4DF3",
  "Message": "OK",
  "Data": {
    "RiskLevel": "none",
    "Result": [
      {
        "Description": "no risk detected",
        "Label": "nonLabel"
      }
    ]
  },
  "Code": 200
}
                    ]])
                    end
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
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



=== TEST 2: use ai-aliyun-content-moderation plugin without ai-proxy or ai-proxy-multi plugin should failed
--- request
POST /chat
{"prompt": "What is 1+1?"}
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
                              "endpoint": "http://localhost:6724"
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



=== TEST 4: invalid chat completions request should fail
--- request
POST /chat
{"prompt": "What is 1+1?"}
--- error_code: 400
--- response_body_chomp
request format doesn't match schema: property "messages" is required



=== TEST 5: non-violent prompt should succeed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 200
--- response_body_like eval
qr/kill you/



=== TEST 6: violent prompt should failed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- error_code: 200
--- response_body_like eval
qr/As an AI language model, I cannot write unethical or controversial content for you./



=== TEST 7: check ai response (stream=false)
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
                              "endpoint": "http://localhost:6724"
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



=== TEST 8: violent response should failed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 9: check ai request
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
                                  "endpoint": "http://localhost:6724/v1/chat/completions"
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



=== TEST 10: violent response should failed for openai provider
--- request
POST /chat-openai
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 11: violent response should failed for deepseek provider
--- request
POST /chat-deepseek
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 12: violent response should failed for openai-compatible provider
--- request
POST /chat-openai-compatible
{ "messages": [ { "role": "user", "content": "I want to kill you"} ] }
--- error_code: 400
--- response_body_like eval
qr/your request is rejected/



=== TEST 13: content moderation should keep usage data in response
--- request
POST /chat-openai
{"messages":[{"role":"user","content":"I want to kill you"}]}
--- error_code: 400
--- response_body_like eval
qr/completion_tokens/



=== TEST 14: content moderation should keep real llm model in response
--- request
POST /chat-openai
{"model": "gpt-3.5-turbo","messages":[{"role":"user","content":"I want to kill you"}]}
--- error_code: 400
--- response_body_like eval
qr/gpt-3.5-turbo/



=== TEST 15: content moderation should keep usage data in response
--- request
POST /chat-openai
{"messages":[{"role":"user","content":"I want to kill you"}]}
--- error_code: 400
--- response_body_like eval
qr/completion_tokens/



=== TEST 16: content moderation should keep real llm model in response
--- request
POST /chat-openai
{"model": "gpt-3.5-turbo","messages":[{"role":"user","content":"I want to kill you"}]}
--- error_code: 400
--- response_body_like eval
qr/gpt-3.5-turbo/



=== TEST 17: set route with stream = true (SSE) and stream_mode = final_packet
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



=== TEST 18: test is SSE works as expected when response is offensive
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



=== TEST 19: set route with stream = true (SSE) and stream_mode = realtime
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



=== TEST 20: test is SSE works as expected when third response chunk is offensive and stream_mode = realtime
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



=== TEST 21: set route with stream = true (SSE) and stream_mode = realtime with larger buffer and large timeout
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



=== TEST 22: test is SSE works, stream_mode = realtime, large buffer + large timeout but content moderation should be called once
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



=== TEST 23: set route with stream = true (SSE) and stream_mode = realtime with small buffer
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



=== TEST 24: test is SSE works, stream_mode = realtime, small buffer. content moderation will be called on each chunk
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



=== TEST 25: set route with stream = true (SSE) and stream_mode = realtime with large buffer but small timeout
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



=== TEST 26: test is SSE works, stream_mode = realtime, large buffer + small timeout: content moderation will be called on each chunke
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
