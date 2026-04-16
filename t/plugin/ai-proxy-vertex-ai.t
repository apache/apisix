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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $extra_init_worker_by_lua = <<_EOC_;
    local gcp_accesstoken = require "apisix.utils.google-cloud-oauth"
    local ttl = 0
    gcp_accesstoken.refresh_access_token = function(self)
        ngx.log(ngx.NOTICE, "[test] mocked gcp_accesstoken called")
        ttl = ttl + 5
        self.access_token_ttl = ttl
        self.access_token = "ya29.c.Kp8B..."
    end
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
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
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/"content"\s*:\s*"1 \+ 1 = 2\."/



=== TEST 3: request embeddings, check values field in response
--- request
POST /anything
{"input": "Your text string goes here"}
--- more_headers
Authorization: Bearer token
X-AI-Fixture: vertex-ai/predictions-embeddings.json
--- error_code: 200
--- response_body eval
qr/"embedding":\[0.0123,-0.0456,0.0789,0.0012\]/



=== TEST 4: request embeddings, check token_count field in response
--- request
POST /anything
{"input": "Your text string goes here"}
--- more_headers
Authorization: Bearer token
X-AI-Fixture: vertex-ai/predictions-embeddings.json
--- error_code: 200
--- response_body eval
qr/"total_tokens":7/



=== TEST 5: set route with right auth gcp service account
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
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": { "max_ttl": 8 }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 6: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/"content"\s*:\s*"1 \+ 1 = 2\."/



=== TEST 7: check gcp access token caching works
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local send_request = function()
                local code, _, body = t("/anything",
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    }
                )
                assert(code == 200, "request should be successful")
                return body
            end
            for i = 1, 6 do
                send_request()
            end

            ngx.sleep(5.5)
            send_request()

            ngx.say("passed")
        }
    }
--- timeout: 7
--- response_body
passed
--- error_log
[test] mocked gcp_accesstoken called
[test] mocked gcp_accesstoken called
set gcp access token in cache with ttl: 5
set gcp access token in cache with ttl: 8



=== TEST 8: set route with multiple instances and gcp service account
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
                                    "name": "vertex-ai-one",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": {}
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                                    }
                                },
                                {
                                    "name": "vertex-ai-multi",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": {}
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 9: check gcp access token caching works
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local send_request = function()
                local code, _, body = t("/anything",
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    }
                )
                assert(code == 200, "request should be successful")
                return body
            end
            for i = 1, 12 do
                send_request()
            end

            ngx.say("passed")
        }
    }
--- timeout: 7
--- response_body
passed
--- error_log
#vertex-ai-one
#vertex-ai-multi



=== TEST 10: set ai-proxy-multi with health checks
--- config
    location /t {
        content_by_lua_block {
            local checks = [[
            "checks": {
                "active": {
                    "timeout": 5,
                    "http_path": "/status/gpt4",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 1,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0"]
                }
            }]]
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "priority": 2,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                                    },
                                    %s
                                },
                                {
                                    "name": "openai-gpt3",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-3"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]], checks)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: check health check works
--- wait: 5
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/"content"\s*:\s*"1 \+ 1 = 2\."/
--- error_log
creating healthchecker for upstream
request head: GET /status/gpt4



=== TEST 12: vertex-predict path function uses ctx.var.llm_model
--- config
    location /t {
        content_by_lua_block {
            local vertex = require("apisix.plugins.ai-providers.vertex-ai")
            local cap = vertex.capabilities["vertex-predict"]

            -- ctx.var.llm_model is set
            local ctx1 = {var = {llm_model = "text-embedding-004"}}
            local path1 = cap.path(
                {project_id = "my-project", region = "us-central1"},
                ctx1
            )

            -- ctx.var.llm_model is set to a different model
            local ctx2 = {var = {llm_model = "textembedding-gecko"}}
            local path2 = cap.path(
                {project_id = "my-project", region = "us-central1"},
                ctx2
            )

            -- ctx is nil (no model)
            local path3 = cap.path(
                {project_id = "my-project", region = "us-central1"},
                nil
            )

            ngx.say(path1)
            ngx.say(path2)
            ngx.say(path3)
        }
    }
--- response_body
/v1/projects/my-project/locations/us-central1/publishers/google/models/text-embedding-004:predict
/v1/projects/my-project/locations/us-central1/publishers/google/models/textembedding-gecko:predict
nil
