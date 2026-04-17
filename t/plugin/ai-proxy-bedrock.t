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
no_shuffle();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $main_config = $block->main_config // <<_EOC_;
        env AWS_EC2_METADATA_DISABLED=true;
        env AWS_REGION=us-east-1;
_EOC_
    $block->set_value("main_config", $main_config);

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name bedrock;
            listen 6724;

            default_type 'application/json';

            location ~ ^/model/.+/converse\$ {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                        return
                    end

                    -- Check SigV4 auth headers
                    local auth_header = ngx.req.get_headers()["authorization"]
                    local amz_date = ngx.req.get_headers()["x-amz-date"]
                    if not auth_header or not amz_date then
                        ngx.status = 403
                        ngx.say(json.encode({
                            message = "Missing Authentication Token"
                        }))
                        return
                    end

                    ngx.req.read_body()
                    local body_data = ngx.req.get_body_data()
                    local body, err = json.decode(body_data)

                    if not body then
                        ngx.status = 400
                        ngx.say(json.encode({ message = "Invalid JSON: " .. (err or "") }))
                        return
                    end

                    -- Verify model is NOT in the body (remove_model = true)
                    if body.model then
                        ngx.status = 400
                        ngx.say(json.encode({
                            message = "model field should not be in request body"
                        }))
                        return
                    end

                    -- Verify request has messages
                    if not body.messages or #body.messages < 1 then
                        ngx.status = 400
                        ngx.say(json.encode({ message = "messages is required" }))
                        return
                    end

                    -- Extract text from first user message
                    local first_content = ""
                    for _, msg in ipairs(body.messages) do
                        if msg.role == "user" and msg.content then
                            for _, block in ipairs(msg.content) do
                                if block.text then
                                    first_content = block.text
                                    break
                                end
                            end
                            break
                        end
                    end

                    -- Return Bedrock Converse response
                    ngx.status = 200
                    ngx.say(json.encode({
                        output = {
                            message = {
                                role = "assistant",
                                content = {{text = "1 + 1 = 2."}}
                            }
                        },
                        stopReason = "end_turn",
                        usage = {
                            inputTokens = 10,
                            outputTokens = 8,
                            totalTokens = 18
                        }
                    }))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with bedrock provider
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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



=== TEST 2: send bedrock converse request
--- request
POST /ai/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"1 \+ 1 = 2\."/



=== TEST 3: send request with system prompt
--- request
POST /ai/converse
{"system":[{"text":"You are a mathematician"}],"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}],"inferenceConfig":{"maxTokens":1024}}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"1 \+ 1 = 2\."/



=== TEST 4: verify token usage in response
--- request
POST /ai/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"inputTokens"\s*:\s*10/



=== TEST 5: schema validation - missing required auth.aws fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/converse2",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-bad",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
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
--- error_code: 400



=== TEST 6: unsupported protocol error - request to non-converse URI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/bedrock-chat",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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



=== TEST 7: send request to non-converse URI - should fail with unsupported protocol
--- request
POST /ai/bedrock-chat
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 400
--- response_body eval
qr/does not support openai-chat protocol/
