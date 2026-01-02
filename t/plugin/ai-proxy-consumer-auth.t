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

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 16726;

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
                        ngx.say([[{"error": "no authorization header"}]])
                        return
                    end

                    if not body.messages or #body.messages < 1 then
                        ngx.status = 400
                        ngx.say([[{ "error": "bad request"}]])
                        return
                    end

                    ngx.status = 200
                    ngx.say([[
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": { "content": "Hello!", "role": "assistant" }
    }
  ],
  "created": 1723780938,
  "model": "gpt-4",
  "usage": { "completion_tokens": 5, "prompt_tokens": 8, "total_tokens": 13 }
}
                    ]])
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: create consumers with provider-specific API keys in labels (encrypted)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "labels": {
                        "openai_api_key_secret": "Bearer sk-proj-jack-openai-key",
                        "gemini_api_key_secret": "Bearer gemini-jack-key"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/consumers/jack/credentials/cred1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "key": "jack-auth-key"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "tom",
                    "labels": {
                        "openai_api_key_secret": "Bearer sk-proj-tom-openai-key",
                        "gemini_api_key_secret": "Bearer gemini-tom-key"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/consumers/tom/credentials/cred2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "key": "tom-auth-key"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: create ai-proxy route with consumer_label auth source
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/openai",
                    "plugins": {
                        "key-auth": {},
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "source": "consumer_label",
                                "header": {
                                    "Authorization": "openai_api_key_secret"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16726"
                            },
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



=== TEST 3: jack's request uses jack's OpenAI API key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, headers, body = t("/openai",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "Hello" }
                    ]
                }]],
                nil,
                {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "jack-auth-key"
                }
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body_like
.*Hello!.*



=== TEST 4: tom's request uses tom's OpenAI API key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, headers, body = t("/openai",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "Hello" }
                    ]
                }]],
                nil,
                {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "tom-auth-key"
                }
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body_like
.*Hello!.*



=== TEST 5: create ai-proxy-multi route with consumer_label auth source
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/multi",
                    "plugins": {
                        "key-auth": {},
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "openai-instance",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": {
                                        "source": "consumer_label",
                                        "header": {
                                            "Authorization": "openai_api_key_secret"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16726"
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



=== TEST 6: ai-proxy-multi with consumer_label - jack's request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, headers, body = t("/multi",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "Hello" }
                    ]
                }]],
                nil,
                {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "jack-auth-key"
                }
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body_like
.*Hello!.*



=== TEST 7: ai-proxy-multi with consumer_label - tom's request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, headers, body = t("/multi",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "Hello" }
                    ]
                }]],
                nil,
                {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "tom-auth-key"
                }
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body_like
.*Hello!.*



=== TEST 8: consumer without required label - should get 401 from upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "bob",
                    "labels": {
                        "other_label": "some_value"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/consumers/bob/credentials/cred3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "key": "bob-auth-key"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 9: bob's request fails - missing openai_api_key_secret label
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, headers, body = t("/openai",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "Hello" }
                    ]
                }]],
                nil,
                {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "bob-auth-key"
                }
            )

            ngx.say(code)
        }
    }
--- response_body
401
--- error_log
consumer label 'openai_api_key_secret' not found for header 'Authorization'
