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


my $resp_file = 't/assets/ai-proxy-response.json';
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

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 16724;

            default_type 'application/json';

            location /anything {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()

                    if body ~= "SELECT * FROM STUDENTS" then
                        ngx.status = 503
                        ngx.say("passthrough doesn't work")
                        return
                    end
                    ngx.say('{"foo", "bar"}')
                }
            }

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
                        ngx.say([[
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": { "content": "1 + 1 = 2.", "role": "assistant" }
    }
  ],
  "created": 1723780938,
  "id": "chatcmpl-9wiSIg5LYrrpxwsr2PubSQnbtod1P",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "system_fingerprint": "fp_abc28019ad",
  "usage": { "completion_tokens": 5, "prompt_tokens": 8, "total_tokens": 10 }
}
                        ]])
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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local configs = {
                {
                    time_window = 60,
                },
                {
                    limit = 30,
                },
                {
                    limit = 30,
                    time_window = 60,
                    rejected_code = 199,
                },
                {
                    limit = 30,
                    time_window = 60,
                    limit_strategy = "invalid",
                },
                {
                    limit = 30,
                    time_window = 60,
                    instances = {
                        {
                            name = "instance1",
                            limit = 30,
                            time_window = 60,
                        },
                        {
                            limit = 30,
                            time_window = 60,
                        }
                    },
                },
                {
                    time_window = 60,
                    instances = {
                        {
                            name = "instance1",
                            limit = 30,
                            time_window = 60,
                        }
                    },
                },
                {
                    limit = 30,
                    time_window = 60,
                    rejected_code = 403,
                    rejected_msg = "rate limit exceeded",
                    limit_strategy = "completion_tokens",
                }
            }
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ai-rate-limiting")
            for _, config in ipairs(configs) do
                local ok, err = plugin.check_schema(config)
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("passed")
                end
            end
            ngx.say("done")
        }
    }
--- response_body
property "limit" is required
property "time_window" is required
property "rejected_code" validation failed: expected 199 to be at least 200
property "limit_strategy" validation failed: matches none of the enum values
property "instances" validation failed: failed to validate item 2: property "name" is required
property "limit" is required
passed
done



=== TEST 2: set route 1, default limit_strategy: total_tokens
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 3: reject the 3th request
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 503]



=== TEST 4: set rejected_code to 403, rejected_msg to "rate limit exceeded"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "rejected_code": 403,
                            "rejected_msg": "rate limit exceeded"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 5: check code and message
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 403]
--- response_body eval
[
    qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/,
    qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/,
    qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/,
    qr/\{"error_msg":"rate limit exceeded"\}/,
]



=== TEST 6: check rate limit headers
--- request
POST /ai
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- response_headers
X-AI-RateLimit-Limit-ai-proxy: 30
X-AI-RateLimit-Remaining-ai-proxy: 29
X-AI-RateLimit-Reset-ai-proxy: 60



=== TEST 7: check rate limit headers after 4 requests
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_header
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 403]
--- response_headers eval
[
    "X-AI-RateLimit-Remaining-ai-proxy: 29",
    "X-AI-RateLimit-Remaining-ai-proxy: 19",
    "X-AI-RateLimit-Remaining-ai-proxy: 9",
    "X-AI-RateLimit-Remaining-ai-proxy: 0",
]



=== TEST 8: set route2 with limit_strategy: completion_tokens
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai2",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 20,
                            "time_window": 45,
                            "limit_strategy": "completion_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 9: reject the 5th request
--- pipelined_requests eval
[
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 200, 503]



=== TEST 10: check rate limit headers
--- request
POST /ai2
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- response_headers
X-AI-RateLimit-Limit-ai-proxy: 20
X-AI-RateLimit-Remaining-ai-proxy: 19
X-AI-RateLimit-Reset-ai-proxy: 45



=== TEST 11: multi-request
--- pipelined_requests eval
[
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_header
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 200, 503]
--- response_headers eval
[
    "X-AI-RateLimit-Remaining-ai-proxy: 19",
    "X-AI-RateLimit-Remaining-ai-proxy: 14",
    "X-AI-RateLimit-Remaining-ai-proxy: 9",
    "X-AI-RateLimit-Remaining-ai-proxy: 4",
    "X-AI-RateLimit-Remaining-ai-proxy: 0",
]



=== TEST 12: request route 1 and route 2
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai2\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 403, 503]
