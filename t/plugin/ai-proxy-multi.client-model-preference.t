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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
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

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local header_auth = ngx.req.get_headers()["authorization"]
                    if not header_auth then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    -- Return different model names based on auth to identify which instance was picked
                    local model = "unknown"
                    if header_auth == "Bearer openai-key" then
                        model = "gpt-4"
                    elseif header_auth == "Bearer deepseek-key" then
                        model = "deepseek-chat"
                    elseif header_auth == "Bearer anthropic-key" then
                        model = "claude-sonnet"
                    end

                    -- Check that models field was stripped from request body
                    if body.models then
                        ngx.status = 400
                        ngx.say('{"error": "models field should have been stripped"}')
                        return
                    end

                    ngx.status = 200
                    ngx.say('{"id":"chatcmpl-test","object":"chat.completion","model":"' .. model .. '","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":5,"total_tokens":10}}')
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: schema validation - allow_client_model_preference defaults to false
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local ok, err = plugin.check_schema({
                instances = {
                    {
                        name = "openai-instance",
                        provider = "openai",
                        weight = 1,
                        auth = {
                            header = {
                                Authorization = "Bearer token"
                            }
                        },
                        options = {
                            model = "gpt-4"
                        }
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: schema validation - allow_client_model_preference set to true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local ok, err = plugin.check_schema({
                allow_client_model_preference = true,
                instances = {
                    {
                        name = "openai-instance",
                        provider = "openai",
                        weight = 1,
                        auth = {
                            header = {
                                Authorization = "Bearer token"
                            }
                        },
                        options = {
                            model = "gpt-4"
                        }
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 3: set up route with client model preference enabled
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
                            "allow_client_model_preference": true,
                            "instances": [
                                {
                                    "name": "openai-instance",
                                    "provider": "openai",
                                    "priority": 1,
                                    "weight": 0,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer openai-key"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                },
                                {
                                    "name": "deepseek-instance",
                                    "provider": "openai",
                                    "priority": 0,
                                    "weight": 0,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer deepseek-key"
                                        }
                                    },
                                    "options": {
                                        "model": "deepseek-chat"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                },
                                {
                                    "name": "anthropic-instance",
                                    "provider": "openai",
                                    "priority": -1,
                                    "weight": 0,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer anthropic-key"
                                        }
                                    },
                                    "options": {
                                        "model": "claude-sonnet"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ]
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



=== TEST 4: client specifies model preference with string shorthand - picks deepseek first
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"models":["deepseek-chat","gpt-4"]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"deepseek-chat"



=== TEST 5: client specifies model preference with object form - picks anthropic first
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"models":[{"provider":"openai","model":"claude-sonnet"},{"provider":"openai","model":"gpt-4"}]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"claude-sonnet"



=== TEST 6: without models field - falls back to server-configured priority (openai first)
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"gpt-4"



=== TEST 7: unrecognized model in preference - ignored, remaining instances used
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"models":["nonexistent-model","deepseek-chat"]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"deepseek-chat"



=== TEST 8: models field is stripped from request body before forwarding
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"models":["gpt-4"]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"gpt-4"
--- error_code: 200



=== TEST 9: set up route with client model preference disabled (default)
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
                                    "name": "openai-instance",
                                    "provider": "openai",
                                    "priority": 1,
                                    "weight": 0,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer openai-key"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                },
                                {
                                    "name": "deepseek-instance",
                                    "provider": "openai",
                                    "priority": 0,
                                    "weight": 0,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer deepseek-key"
                                        }
                                    },
                                    "options": {
                                        "model": "deepseek-chat"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ]
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



=== TEST 10: models field ignored when allow_client_model_preference is false - uses server priority
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"models":["deepseek-chat"]}
--- more_headers
Content-Type: application/json
--- response_body_like
"model":"gpt-4"
