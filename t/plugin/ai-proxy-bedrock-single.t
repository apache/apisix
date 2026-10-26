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
  - ai-proxy
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set route with bedrock provider (single ai-proxy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/single-ai/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 2: send bedrock converse request
--- request
POST /single-ai/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/



=== TEST 3: send request with system prompt
--- request
POST /single-ai/converse
{"system":[{"text":"You are a mathematician"}],"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}],"inferenceConfig":{"maxTokens":1024}}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/



=== TEST 4: verify token usage in response
--- request
POST /single-ai/converse
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
                    "uri": "/single-ai/converse2",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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
--- error_code: 400



=== TEST 6: unsupported protocol error - request to non-converse URI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/single-ai/bedrock-chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 7: send request to non-converse URI - should fail with unsupported protocol
--- request
POST /single-ai/bedrock-chat
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
                    "uri": "/single-ai/arn/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 9: send request with ARN model (passes through SigV4 + URL encoding)
--- request
POST /single-ai/arn/converse
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
                    "uri": "/single-ai/session/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 11: send request with session_token (verify x-amz-security-token propagation)
--- request
POST /single-ai/session/converse
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
                    "uri": "/single-ai/default/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 13: model from request body — no options.model on route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/8',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/single-ai/body-model-only/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 14: send request with body-supplied model (path is built from body.model)
--- request
POST /single-ai/body-model-only/converse
{"model":"anthropic.claude-3-5-sonnet-20241022-v2:0","messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse}



=== TEST 15: missing model both on route and in body — clear 400 error
--- request
POST /single-ai/body-model-only/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 400
--- response_body eval
qr/could not resolve upstream path/



=== TEST 16: route for streaming (single ai-proxy, no path on endpoint)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/single-ai/stream/converse",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "bedrock",
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



=== TEST 17: stream request hits /converse-stream and forwards EventStream bytes
--- request
POST /single-ai/stream/converse
{"stream":true,"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- error_code: 200
--- response_body eval
qr/messageStart.*contentBlockDelta.*Hello.*messageStop.*metadata/s
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse-stream}
--- response_headers
Content-Type: application/vnd.amazon.eventstream



=== TEST 18: non-stream request on the same route still hits /converse
--- request
POST /single-ai/stream/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
--- error_log eval
qr{\[test\] received uri: /model/anthropic\.claude-3-5-sonnet-20241022-v2%3A0/converse(?!-stream)}



=== TEST 19: Bedrock cache usage matches LiteLLM for both response modes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local bedrock = require("apisix.plugins.ai-protocols.bedrock-converse")
            local loader = require("lib.fixture_loader")
            -- Expected usage was differentialed against LiteLLM 3d526bfe transform_usage.
            local cases = core.json.decode(assert(loader.load(
                "bedrock/converse-cache-usage-cases.json")), { null_as_nil = true })
            for _, case in ipairs(cases) do
                local usage, raw = bedrock.extract_usage({ usage = case.raw })
                assert(raw == case.raw, case.name .. " raw usage preserved")
                local result = bedrock.parse_sse_event({
                    headers = { [":event-type"] = "metadata" },
                    payload = core.json.encode({ usage = case.raw }),
                }, {}, {})
                assert(result.type == "usage_and_done", case.name)
                for key, expected in pairs(case.expected) do
                    assert(usage[key] == expected, case.name .. " non-stream " .. key)
                    assert(result.usage[key] == expected, case.name .. " stream " .. key)
                end
                assert(core.json.stably_encode(result.raw_usage)
                       == core.json.stably_encode(case.raw), case.name .. " stream raw usage")
            end
            local usage = bedrock.extract_usage({ usage = {} })
            assert(usage.prompt_tokens == 0 and usage.total_tokens == 0, "empty usage")
            assert(bedrock.extract_usage({}) == nil, "missing usage")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 20: non-streaming cache tokens reach the LLM logging variables
--- request
POST /single-ai/stream/converse
{"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- more_headers
X-AI-Fixture: bedrock/converse-with-cache.json
--- response_body_like eval
qr/"cacheReadInputTokens":20/
--- access_log eval
qr/ 60 8 68 false false 0 \S* 20 30 0 /
--- no_error_log
[error]



=== TEST 21: streaming cache tokens reach the LLM logging variables
--- request
POST /single-ai/stream/converse
{"stream":true,"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- more_headers
X-AI-Fixture: bedrock/converse-streaming-with-cache.bin
--- response_body_like eval
qr/metadata/
--- access_log eval
qr/ 60 8 68 true false 0 \S* 20 30 0 /
--- no_error_log
[error]
