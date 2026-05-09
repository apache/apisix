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
_EOC_
    $block->set_value("main_config", $main_config);

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
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
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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
qr/"text"\s*:\s*"Hello!"/



=== TEST 3: send request with system prompt
--- request
POST /ai/converse
{"system":[{"text":"You are a mathematician"}],"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}],"inferenceConfig":{"maxTokens":1024}}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/



=== TEST 4: verify token usage in response
--- request
POST /ai/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"inputTokens"\s*:\s*13/



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
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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



=== TEST 8: set route with inference profile ARN as model
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/arn/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-arn",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/test123"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/model/arn%3Aaws%3Abedrock%3Aus-east-1%3A123456789012%3Aapplication-inference-profile%2Ftest123/converse"
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



=== TEST 9: send request with ARN model (passes through SigV4 + URL encoding)
--- request
POST /ai/arn/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
--- error_log eval
qr{\[test\] received uri: /model/arn%3Aaws%3Abedrock%3Aus-east-1%3A123456789012%3Aapplication-inference-profile%2Ftest123/converse}



=== TEST 10: set route with session_token in auth.aws
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/5',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/session/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-session",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                                            "session_token": "FwoGZXIvYXdzEXAMPLESESSIONTOKEN"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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



=== TEST 11: send request with session_token (verify x-amz-security-token propagation)
--- request
POST /ai/session/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/session_token_seen=FwoGZXIvYXdzEXAMPLESESSIONTOKEN/



=== TEST 12: route with default endpoint (no override) passes schema validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/6',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/default/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-default-endpoint",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
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
--- response_body
passed



=== TEST 13: route without options.model passes schema validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/7',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/body-model/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-body-model",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/model/anthropic.claude-3-5-sonnet-20241022-v2:0/converse"
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



=== TEST 14: model from request body — no options.model on route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/8',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/body-model-only/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-body-only",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980"
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



=== TEST 15: send request with body-supplied model (path is built from body.model)
--- request
POST /ai/body-model-only/converse
{"model":"anthropic.claude-3-5-sonnet-20241022-v2:0","messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse}



=== TEST 16: missing model both on route and in body — clear 400 error
--- request
POST /ai/body-model-only/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 400
--- response_body eval
qr/could not resolve upstream path/



=== TEST 17: route for streaming (no path on endpoint, model from options)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/stream/converse",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "bedrock-stream",
                                    "provider": "bedrock",
                                    "weight": 1,
                                    "auth": {
                                        "aws": {
                                            "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                            "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                        }
                                    },
                                    "provider_conf": {
                                        "region": "us-east-1"
                                    },
                                    "options": {
                                        "model": "anthropic.claude-3-5-sonnet-20241022-v2:0"
                                    },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980"
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



=== TEST 18: stream request hits /converse-stream and forwards EventStream bytes
--- request
POST /ai/stream/converse
{"stream":true,"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- error_code: 200
--- response_body eval
qr/messageStart.*contentBlockDelta.*Hello.*messageStop.*metadata/s
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse-stream}
--- response_headers
Content-Type: application/vnd.amazon.eventstream



=== TEST 19: stream request aggregates response text and token usage
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port
                .. "/ai/stream/converse", {
                method = "POST",
                headers = {["Content-Type"] = "application/json"},
                body = [[{"stream":true,"messages":[{"role":"user","content":[{"text":"hi"}]}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
            -- Body is binary EventStream; expose payload-bearing keywords so the
            -- test can assert frame ordering and token-bearing metadata payload.
            local body = res.body
            local found = {}
            for _, name in ipairs({"messageStart", "contentBlockDelta",
                                   "Hello", "messageStop", "metadata",
                                   "inputTokens", "outputTokens"}) do
                if body:find(name, 1, true) then
                    found[#found + 1] = name
                end
            end
            ngx.say(table.concat(found, ","))
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
messageStart,contentBlockDelta,Hello,messageStop,metadata,inputTokens,outputTokens
--- error_log eval
qr/got token usage from ai service/



=== TEST 20: non-stream request still hits /converse (control)
--- request
POST /ai/stream/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse(?!-stream)}
