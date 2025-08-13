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

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.exec("\@chat")
                }
            }


            location /delay/v1/chat/completions {
                content_by_lua_block {
                    ngx.sleep(2)
                    ngx.exec("\@chat")
                }
            }

            location \@chat {
                content_by_lua_block {
                    ngx.status = 200
                    ngx.say([[
{
  "choices": [
    {
      "message": {
        "content": "1 + 1 = 2.",
        "role": "assistant"
      }
    }
  ],
  "usage": {
    "completion_tokens": 5,
    "prompt_tokens": 8,
    "total_tokens": 13
  }
}
                    ]])
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
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
                                            "endpoint": "http://localhost:6724"
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
{"messages":[{"role":"user","content":"What is 1+1?"}]}
--- error_code: 200



=== TEST 3: assert llm_lantency_bucket metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_bucket\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4",le="\d+"\} 1/



=== TEST 4: assert llm_lantency_count metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4"\} 1/



=== TEST 5: assert llm_lantency_sum metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_latency_count\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4"\} \d+/



=== TEST 6: assert llm_prompt_tokens metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_prompt_tokens\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4"\} 8/



=== TEST 7: assert llm_completion_tokens metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_completion_tokens\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4"\} 5/



=== TEST 8: assert llm_active_connections metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_llm_active_connections\{.*route_id="1",.*,node="openai-gpt4".*.*request_type="ai_chat",llm_model="gpt-4"\} 0/



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
                                            "endpoint": "http://localhost:6724/delay/v1/chat/completions"
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
