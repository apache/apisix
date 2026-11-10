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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
    my $user_yaml_config = <<_EOC_;
plugin_attr:
    prometheus:
        refresh_interval: 0.1
plugins:
  - ai-proxy-multi
  - prometheus
  - public-api
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: create a route with prometheus and ai-proxy-multi plugin
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "ai-proxy-multi": {
                                "instances": [
                                    {
                                        "name": "openai-gpt4",
                                        "provider": "openai",
                                        "weight": 1,
                                        "auth": {
                                            "header": {
                                                "Authorization": "Bearer token"
                                            }
                                        },
                                        "options": {
                                            "model": "gpt-4"
                                        },
                                        "override": {
                                            "endpoint": "http://127.0.0.1:1980"
                                        }
                                    }
                                ]
                            }
                        },
                        "uri": "/chat"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local _, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 2



=== TEST 2: send a chat request
--- request
POST /chat
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-3"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 3: assert llm_lantency_bucket metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_bucket\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4",le="\d+"\} 1/



=== TEST 4: assert llm_lantency_count metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 1/



=== TEST 5: assert llm_lantency_sum metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} \d+/



=== TEST 6: assert llm_prompt_tokens metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_prompt_tokens\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 8/



=== TEST 7: assert llm_completion_tokens metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_completion_tokens\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 5/



=== TEST 8: assert llm_active_connections metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_active_connections\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 0/



=== TEST 9: change ai-proxy-multi to use a slower ai endpoint
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "ai-proxy-multi": {
                                "instances": [
                                    {
                                        "name": "openai-gpt4",
                                        "provider": "openai",
                                        "weight": 1,
                                        "auth": {
                                            "header": {
                                                "Authorization": "Bearer token"
                                            }
                                        },
                                        "options": {
                                            "model": "gpt-4"
                                        },
                                        "override": {
                                            "endpoint": "http://127.0.0.1:1980/delay/v1/chat/completions"
                                        }
                                    }
                                ]
                            }
                        },
                        "uri": "/chat"
                    }]],
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local _, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n"



=== TEST 10: assert llm_active_connections metric when the ai endpoint is slow
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res_list = {}
            for i = 1, 3 do
                local url = "http://127.0.0.1:" .. ngx.var.server_port .. "/chat"
                local function send_chat_request(idx)
                    local http = require "resty.http"
                    local httpc = http.new()
                    local res = httpc:request_uri(
                        url,
                        {
                            method = "POST",
                            body = [[ {"messages":[{"role":"user","content":"What is 1+1?"}]} ]],
                            headers = {
                                ["X-AI-Fixture"] = "prometheus/chat-basic.json",
                            },
                        })
                    res_list[idx] = res
                end
                ngx.timer.at(0, send_chat_request, i)
            end
            ngx.sleep(1)
            local http = require "resty.http"
            local httpc = http.new()
            local metric_resp = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics")
            if not string.find(metric_resp.body, [[apisix_llm_active_connections{.*} 3]]) then
                ngx.say(metric_resp.body)
                ngx.say("llm_active_connections should be 3")
                return
            end
            ngx.sleep(1)
            for _, res in ipairs(res_list) do
                if res.status ~= 200 then
                    ngx.say("failed to send chat request")
                    return
                end
            end
            metric_resp = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics")
            if not string.find(metric_resp.body, [[apisix_llm_active_connections{.*} 0]]) then
                ngx.say(metric_resp.body)
                ngx.say("llm_active_connections should be 0 after all requests are done")
                return
            end
            ngx.say("success")
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 11: create a non-streaming route for token distribution histograms
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/3",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "ai-proxy-multi": {
                                "instances": [
                                    {
                                        "name": "openai-gpt4",
                                        "provider": "openai",
                                        "weight": 1,
                                        "auth": {
                                            "header": {
                                                "Authorization": "Bearer token"
                                            }
                                        },
                                        "options": {
                                            "model": "gpt-4"
                                        },
                                        "override": {
                                            "endpoint": "http://127.0.0.1:1980"
                                        }
                                    }
                                ]
                            }
                        },
                        "uri": "/chat-dist"
                    }]],
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local _, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 12: send a non-streaming chat request
--- request
POST /chat-dist
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-3"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 13: assert llm_prompt_tokens_dist_count metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_prompt_tokens_dist_count\{.*route_id="3",.*,node="openai-gpt4".*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 1/



=== TEST 14: assert llm_completion_tokens_dist_count metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_completion_tokens_dist_count\{.*route_id="3",.*,node="openai-gpt4".*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 1/



=== TEST 15: llm_latency type=ttft is not recorded for non-streaming requests
--- request
GET /apisix/prometheus/metrics
--- response_body_unlike eval
qr/apisix_llm_latency_count\{type="ttft",.*route_id="3"/



=== TEST 16: create a streaming route for the TTFT histogram
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/4",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "ai-proxy-multi": {
                                "instances": [
                                    {
                                        "name": "openai-gpt4",
                                        "provider": "openai",
                                        "weight": 1,
                                        "auth": {
                                            "header": {
                                                "Authorization": "Bearer token"
                                            }
                                        },
                                        "options": {
                                            "model": "gpt-4"
                                        },
                                        "override": {
                                            "endpoint": "http://127.0.0.1:1980"
                                        }
                                    }
                                ]
                            }
                        },
                        "uri": "/chat-stream"
                    }]],
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local _, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 17: send a streaming chat request
--- request
POST /chat-stream
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-3", "stream": true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
Content-Type: text/event-stream



=== TEST 18: assert llm_latency type=ttft count for the streaming request
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{type="ttft",.*route_id="4",.*,node="openai-gpt4".*request_type="ai_stream",request_llm_model="gpt-3",llm_model="gpt-4"\} 1/



=== TEST 19: assert llm_latency type=ttft bucket for the streaming request
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_bucket\{type="ttft",.*route_id="4",.*,node="openai-gpt4".*request_type="ai_stream",request_llm_model="gpt-3",llm_model="gpt-4",le="\d+"\} 1/



=== TEST 20: assert llm_latency type=total is also recorded for the streaming request
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{type="total",.*route_id="4",.*,node="openai-gpt4".*request_type="ai_stream",request_llm_model="gpt-3",llm_model="gpt-4"\} 1/



=== TEST 21: send a chat request whose model name exceeds the 128-byte label cap
--- request eval
"POST /chat\n" .
qq#{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "@{[ 'a' x 200 ]}"}#
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 22: request_llm_model label is truncated to 128 bytes (cardinality DoS guard)
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_llm_prompt_tokens\{.*request_llm_model="a{128}",llm_model="gpt-4"\}/
--- response_body_unlike eval
qr/request_llm_model="a{129}"/



=== TEST 23: disable request_llm_model / llm_model labels via plugin_metadata disabled_labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, body = t("/apisix/admin/plugin_metadata/prometheus",
                ngx.HTTP_PUT,
                [[{
                    "disabled_labels": {
                        "llm_prompt_tokens": ["request_llm_model", "llm_model"]
                    }
                }]]
            )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 24: send a chat request with a distinct model
--- request
POST /chat
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "distinct-model-aaa"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 25: send another chat request with a different distinct model
--- request
POST /chat
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "distinct-model-bbb"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 26: disabled_labels collapses distinct client models to one empty-valued series
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_llm_prompt_tokens\{.*request_llm_model="",llm_model=""\}/
--- response_body_unlike eval
qr/apisix_llm_prompt_tokens\{.*request_llm_model="distinct-model-/



=== TEST 27: create a route to check llm_latency excludes error responses
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/5",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "ai-proxy-multi": {
                                "instances": [
                                    {
                                        "name": "openai-gpt4",
                                        "provider": "openai",
                                        "weight": 1,
                                        "auth": {
                                            "header": {
                                                "Authorization": "Bearer token"
                                            }
                                        },
                                        "options": {
                                            "model": "gpt-4"
                                        },
                                        "override": {
                                            "endpoint": "http://127.0.0.1:1980"
                                        }
                                    }
                                ]
                            }
                        },
                        "uri": "/chat-guard"
                    }]],
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local _, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 28: a served response records one llm_latency observation
--- request
POST /chat-guard
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-3"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
--- error_code: 200



=== TEST 29: a 429 error response goes through the same route
--- request
POST /chat-guard
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-3"}
--- more_headers
X-AI-Fixture: prometheus/chat-basic.json
X-AI-Fixture-Status: 429
--- error_code: 429



=== TEST 30: the error response is excluded, so the count stays 1 not 2
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{type="total",.*route_id="5",.*,node="openai-gpt4".*request_type="ai_chat",request_llm_model="gpt-3",llm_model="gpt-4"\} 1\n/
