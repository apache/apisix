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
  - key-auth
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
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

=== TEST 1: create a regular route with prometheus plugin
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "plugins": {
                            "prometheus": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                    }]],
                },
                {
                    url = "/apisix/admin/consumers",
                    data = [[{
                        "username": "test-consumer",
                        "plugins": {
                            "key-auth": {
                                "key": "test-key-for-prometheus"
                            }
                        }
                    }]],
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "prometheus": {},
                            "key-auth": {},
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
passed
passed



=== TEST 2: send a regular request
--- request
GET /hello
--- response_body
hello world



=== TEST 3: assert llm metrics are not generated for the regular request
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local metric_resp = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics")

            if not metric_resp then
                ngx.say("failed to fetch metrics")
                return
            end

            local body = metric_resp.body
            local has_error = false
            for line in string.gmatch(body, "[^\r\n]+") do
                if string.find(line, "apisix_llm_") then
                    has_error = true
                    ngx.say("llm metric found: ", line)
                    return
                end
            end

            if not has_error then
                ngx.say("success")
            end
        }
    }
--- request
GET /t
--- response_body
success
