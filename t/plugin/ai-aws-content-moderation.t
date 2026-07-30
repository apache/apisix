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

    my $main_config = $block->main_config // <<_EOC_;
        env AWS_REGION=us-east-1;
_EOC_

    $block->set_value("main_config", $main_config);

    # Mock AWS Comprehend detectToxicContent: looks up each extracted text
    # segment in the canned responses fixture and answers with one result per
    # segment, the way the real service does.
    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 2668;

            default_type 'application/json';

            location / {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local open = io.open
                    local f = open('t/assets/content-moderation-responses.json', "r")
                    local resp = f:read("*a")
                    f:close()

                    if not resp then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to open response.json file")
                    end

                    local responses = json.decode(resp)
                    if not responses then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to decode response.json contents")
                    end

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    if not body then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to get request body: ", err)
                    end

                    body, err = json.decode(body)
                    if not body then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to decoded request body: ", err)
                    end
                    local segments = body.TextSegments
                    ngx.log(ngx.WARN, "comprehend call: segments=", #segments,
                            " connection_requests=", ngx.var.connection_requests)

                    -- Comprehend takes at most 10 segments of 1 KB each, 10 KB
                    -- for the list; over that it answers 400. Enforce it here so
                    -- the tests catch content that is sent unsplit.
                    local total = 0
                    for _, segment in ipairs(segments) do
                        total = total + #segment.Text
                    end
                    if #segments > 10 or total > 10240 then
                        ngx.status = 400
                        ngx.say(json.encode({
                            __type = "TextSizeLimitExceededException",
                            Message = "Input text size exceeds limit."
                        }))
                        return
                    end

                    local results = {}
                    for i, segment in ipairs(segments) do
                        local text = segment.Text
                        if #text > 1024 then
                            ngx.status = 400
                            ngx.say(json.encode({
                                __type = "TextSizeLimitExceededException",
                                Message = "Input text size exceeds limit."
                            }))
                            return
                        end

                        local canned = responses[text]

                        -- Response-side text is free-form LLM output, not a
                        -- fixture key, so fall back to flagging anything violent.
                        if not canned then
                            if text:find("kill", 1, true) then
                                canned = responses["toxic"]
                            else
                                canned = responses["good_request"]
                            end
                        end
                        results[i] = canned.ResultList[1]
                    end

                    ngx.say(json.encode({ ResultList = results }))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: sanity, ai-proxy + moderation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "deny_code": 400
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



=== TEST 2: toxic request should fail
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "toxic" } ] }
--- error_code: 400
--- response_body_like eval
qr/request body exceeds toxicity threshold/



=== TEST 3: good request should pass
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- error_code: 200
--- response_body_like eval
qr/good_request/



=== TEST 4: profanity filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "moderation_categories": { "PROFANITY": 0.5 },
                            "deny_code": 400
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



=== TEST 5: profane request should fail
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "profane" } ] }
--- error_code: 400
--- response_body_like eval
qr/request body exceeds PROFANITY threshold/



=== TEST 6: very profane request should also fail
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "very_profane" } ] }
--- error_code: 400
--- response_body_like eval
qr/request body exceeds PROFANITY threshold/



=== TEST 7: good_request should pass
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- error_code: 200
--- response_body_like eval
qr/good_request/



=== TEST 8: set profanity = 0.7 (allow profane request but disallow very_profane)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "moderation_categories": { "PROFANITY": 0.7 },
                            "deny_code": 400
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



=== TEST 9: profane request should pass profanity check but fail toxicity check
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "profane" } ] }
--- error_code: 400
--- response_body_like eval
qr/request body exceeds toxicity threshold/



=== TEST 10: profane_but_not_toxic request should pass
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "profane_but_not_toxic" } ] }
--- error_code: 200
--- response_body_like eval
qr/profane_but_not_toxic/



=== TEST 11: but very profane request will fail
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "very_profane" } ] }
--- error_code: 400
--- response_body_like eval
qr/request body exceeds PROFANITY threshold/



=== TEST 12: good_request should pass
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- error_code: 200
--- response_body_like eval
qr/good_request/



=== TEST 13: setup route without ai-proxy, default fail_mode (skip)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1980": 1 }
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



=== TEST 14: request without ai-proxy passes through unchecked (skip)
--- request
POST /echo
{ "messages": [ { "role": "user", "content": "toxic" } ] }
--- error_code: 200
--- response_body_like eval
qr/toxic/
--- error_log
ai-aws-content-moderation skipped: no ai instance picked



=== TEST 15: setup route without ai-proxy, fail_mode=error
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "fail_mode": "error"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1980": 1 }
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



=== TEST 16: request without ai-proxy is rejected when fail_mode=error
--- request
POST /echo
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- error_code: 500
--- response_body_chomp
no ai instance picked, ai-aws-content-moderation plugin must be used with ai-proxy or ai-proxy-multi plugin



=== TEST 17: schema check: deny_code must be within [200, 599]
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local conf = {
                comprehend = {
                    access_key_id = "a",
                    secret_access_key = "s",
                    region = "us-east-1"
                }
            }
            for _, code in ipairs({199, 600}) do
                conf.deny_code = code
                ngx.say(code, ": ", plugin.check_schema(conf) and "accepted" or "rejected")
            end
            conf.deny_code = 403
            ngx.say("403: ", plugin.check_schema(conf) and "accepted" or "rejected")
        }
    }
--- response_body
199: rejected
600: rejected
403: accepted



=== TEST 18: set route with check_response enabled (non-streaming)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400
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



=== TEST 19: toxic LLM response is denied
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- more_headers
X-AI-Fixture: aws/chat-with-harmful.json
--- error_code: 400
--- response_body_like eval
qr/response body exceeds toxicity threshold/



=== TEST 20: clean LLM response passes through
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- more_headers
X-AI-Fixture: aws/chat-safe.json
--- error_code: 200
--- response_body_like eval
qr/How can I assist you today/



=== TEST 21: set route with default deny_code and a custom deny_message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "deny_message": "the response was withheld"
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



=== TEST 22: response deny is a provider-compatible completion the client can parse
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- more_headers
X-AI-Fixture: aws/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/(?=.*"object":"chat\.completion")(?=.*the response was withheld)/s



=== TEST 23: set route with check_response disabled (default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false
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



=== TEST 24: toxic LLM response passes when check_response is off
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- more_headers
X-AI-Fixture: aws/chat-with-harmful.json
--- error_code: 200
--- response_body_like eval
qr/I will kill you/



=== TEST 25: set route with stream = true (SSE) and stream_check_mode = final_packet
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "stream_check_mode": "final_packet"
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



=== TEST 26: final_packet annotates the streamed response with the verdict
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ], "stream": true }
--- more_headers
X-AI-Fixture: aws/chat-streaming-harmful.sse
X-AI-Fixture-Flush-Events: true
--- error_code: 200
--- response_body_like eval
qr/"risk_level":"high"/



=== TEST 27: set route with stream_check_mode = realtime and a small batch size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "deny_message": "the response was withheld",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 5
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



=== TEST 28: realtime cuts the stream off as soon as a batch is toxic
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ], "stream": true }
--- more_headers
X-AI-Fixture: aws/chat-streaming-harmful.sse
X-AI-Fixture-Flush-Events: true
--- error_code: 200
--- response_body_like eval
qr/the response was withheld/
--- response_body_unlike eval
qr/right now!/



=== TEST 29: response moderation is skipped when upstream returns an error status
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local ctx = {
                picked_ai_instance = { provider = "openai" },
                var = { request_type = "ai_stream" },
            }
            local conf = {
                comprehend = {
                    access_key_id = "access",
                    secret_access_key = "secret",
                    region = "us-east-1"
                },
                check_response = true,
                stream_check_mode = "realtime",
                stream_check_cache_size = 128,
                stream_check_interval = 3,
            }
            ngx.status = 400
            local code, msg = plugin.lua_body_filter(conf, ctx, {}, "body")
            ngx.status = 200
            ngx.say("code:", code or "nil", ", msg:", msg or "nil")
        }
    }
--- response_body
code:nil, msg:nil
--- error_log
skip response check because upstream returned error status: 400



=== TEST 30: schema check: streaming knobs are validated
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local function conf(extra)
                local c = {
                    comprehend = {
                        access_key_id = "a",
                        secret_access_key = "s",
                        region = "us-east-1"
                    }
                }
                for k, v in pairs(extra or {}) do
                    c[k] = v
                end
                return c
            end

            ngx.say("bad mode: ",
                plugin.check_schema(conf({stream_check_mode = "eventually"}))
                    and "accepted" or "rejected")
            ngx.say("zero cache size: ",
                plugin.check_schema(conf({stream_check_cache_size = 0}))
                    and "accepted" or "rejected")
            ngx.say("tiny interval: ",
                plugin.check_schema(conf({stream_check_interval = 0.01}))
                    and "accepted" or "rejected")

            local c = conf()
            plugin.check_schema(c)
            ngx.say("defaults: ", c.check_response and "on" or "off", " ",
                    c.stream_check_mode, " ", c.stream_check_cache_size, " ",
                    c.stream_check_interval)
        }
    }
--- response_body
bad mode: rejected
zero cache size: rejected
tiny interval: rejected
defaults: off final_packet 128 3



=== TEST 31: final_packet annotates an empty streamed response with risk_level none
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local ctx = {
                picked_ai_instance = { provider = "openai" },
                ai_client_protocol = "openai-chat",
                var = {
                    request_type = "ai_stream",
                    llm_response_text = "",
                    llm_request_done = true,
                },
            }
            local conf = {
                comprehend = {
                    access_key_id = "access",
                    secret_access_key = "secret",
                    region = "us-east-1",
                    endpoint = "http://localhost:2668"
                },
                check_response = true,
                stream_check_mode = "final_packet",
            }
            plugin.check_schema(conf)
            local body = 'data: {"choices":[{"delta":{"content":""}}]}\n\n'
            local code, new_body = plugin.lua_body_filter(conf, ctx, {}, body)
            ngx.say("code:", code or "nil")
            ngx.say("risk_level:", ctx.var.llm_content_risk_level or "nil")
            ngx.say(new_body)
        }
    }
--- response_body_like eval
qr/code:nil\nrisk_level:none\n.*"risk_level":"none"/s



=== TEST 32: final_packet leaves a non-object SSE data frame untouched (no crash)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local ctx = {
                picked_ai_instance = { provider = "openai" },
                ai_client_protocol = "openai-chat",
                var = {
                    request_type = "ai_stream",
                    llm_response_text = "good_request",
                    llm_request_done = true,
                },
            }
            local conf = {
                comprehend = {
                    access_key_id = "access",
                    secret_access_key = "secret",
                    region = "us-east-1",
                    endpoint = "http://localhost:2668"
                },
                check_response = true,
                stream_check_mode = "final_packet",
            }
            plugin.check_schema(conf)
            -- first frame is a bare scalar (not indexable), second is a valid object
            local body = 'data: 12345\n\n'
                      .. 'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
            local code, new_body = plugin.lua_body_filter(conf, ctx, {}, body)
            ngx.say("code:", code or "nil")
            ngx.say(new_body)
        }
    }
--- response_body_like eval
qr/code:nil\n.*data: 12345.*"risk_level":"none"/s
--- no_error_log
[error]



=== TEST 33: set route with the default check length limits
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "deny_code": 400
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



=== TEST 34: request over 1 KB is split into segments Comprehend accepts
--- request eval
"POST /chat
{ \"messages\": [ { \"role\": \"user\", \"content\": \"" . ("a" x 2395) . " kill\" } ] }"
--- error_code: 400
--- response_body_like eval
qr/request body exceeds toxicity threshold/
--- grep_error_log eval
qr/comprehend call: segments=\d+/
--- grep_error_log_out
comprehend call: segments=3



=== TEST 35: clean request over 1 KB passes
--- request eval
"POST /chat
{ \"messages\": [ { \"role\": \"user\", \"content\": \"" . ("a" x 2400) . "\" } ] }"
--- error_code: 200
--- grep_error_log eval
qr/comprehend call: segments=\d+/
--- grep_error_log_out
comprehend call: segments=3



=== TEST 36: set route with a check length limit that needs several batches
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "request_check_length_limit": 100
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



=== TEST 37: segments past the tenth go in a second call on the same connection
--- request eval
"POST /chat
{ \"messages\": [ { \"role\": \"user\", \"content\": \"" . ("a" x 1100) . "\" } ] }"
--- error_code: 200
--- grep_error_log eval
qr/comprehend call: segments=\d+ connection_requests=\d+/
--- grep_error_log_out
comprehend call: segments=10 connection_requests=1
comprehend call: segments=1 connection_requests=2



=== TEST 38: same route with keepalive turned off
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "request_check_length_limit": 100,
                            "keepalive": false
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



=== TEST 39: without keepalive every batch opens a new connection
--- request eval
"POST /chat
{ \"messages\": [ { \"role\": \"user\", \"content\": \"" . ("a" x 1100) . "\" } ] }"
--- error_code: 200
--- grep_error_log eval
qr/comprehend call: segments=\d+ connection_requests=\d+/
--- grep_error_log_out
comprehend call: segments=10 connection_requests=1
comprehend call: segments=1 connection_requests=1



=== TEST 40: set route with check_response enabled (non-streaming)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "deny_code": 400
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



=== TEST 41: toxic LLM response over 1 KB is denied
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ] }
--- more_headers
X-AI-Fixture: aws/chat-long-harmful.json
--- error_code: 400
--- response_body_like eval
qr/response body exceeds toxicity threshold/
--- grep_error_log eval
qr/comprehend call: segments=\d+/
--- grep_error_log_out
comprehend call: segments=2



=== TEST 42: set route with stream_check_mode = realtime and a batch over 1 KB
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" }
                        },
                        "ai-aws-content-moderation": {
                            "comprehend": {
                                "access_key_id": "access",
                                "secret_access_key": "ea+secret",
                                "region": "us-east-1",
                                "endpoint": "http://localhost:2668"
                            },
                            "check_request": false,
                            "check_response": true,
                            "deny_message": "the response was withheld",
                            "stream_check_mode": "realtime",
                            "stream_check_cache_size": 1500
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



=== TEST 43: a realtime batch over 1 KB is still moderated
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "good_request" } ], "stream": true }
--- more_headers
X-AI-Fixture: aws/chat-streaming-long-harmful.sse
X-AI-Fixture-Flush-Events: true
--- error_code: 200
--- response_body_like eval
qr/the response was withheld/
--- error_log
comprehend call: segments=2
--- no_error_log
failed to get moderation results from response



=== TEST 44: final_packet does not annotate a verdict it could not compute
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local ctx = {
                picked_ai_instance = { provider = "openai" },
                ai_client_protocol = "openai-chat",
                var = {
                    request_type = "ai_stream",
                    llm_response_text = "hello there",
                    llm_request_done = true,
                    -- the request check already ran and found nothing
                    llm_content_risk_level = "none",
                },
            }
            local conf = {
                comprehend = {
                    access_key_id = "access",
                    secret_access_key = "secret",
                    region = "us-east-1",
                    -- nothing listening, so the response is never scored
                    endpoint = "http://localhost:2669"
                },
                check_response = true,
                stream_check_mode = "final_packet",
            }
            plugin.check_schema(conf)
            local body = 'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
            local code, new_body = plugin.lua_body_filter(conf, ctx, {}, body)
            ngx.say("code:", code or "nil")
            ngx.say("annotated:", new_body:find("risk_level", 1, true) and "yes" or "no")
        }
    }
--- response_body
code:nil
annotated:no
--- error_log
response was not scored, streaming without a risk_level annotation



=== TEST 45: schema check: length limits are bounded by Comprehend's 1 KB cap
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-aws-content-moderation")
            local function conf(extra)
                local c = {
                    comprehend = {
                        access_key_id = "a",
                        secret_access_key = "s",
                        region = "us-east-1"
                    }
                }
                for k, v in pairs(extra or {}) do
                    c[k] = v
                end
                return c
            end

            ngx.say("request limit over 1 KB: ",
                plugin.check_schema(conf({request_check_length_limit = 1025}))
                    and "accepted" or "rejected")
            ngx.say("response limit over 1 KB: ",
                plugin.check_schema(conf({response_check_length_limit = 1025}))
                    and "accepted" or "rejected")
            ngx.say("zero request limit: ",
                plugin.check_schema(conf({request_check_length_limit = 0}))
                    and "accepted" or "rejected")
            ngx.say("1 KB limit: ",
                plugin.check_schema(conf({response_check_length_limit = 1024}))
                    and "accepted" or "rejected")

            local c = conf()
            plugin.check_schema(c)
            ngx.say("defaults: ", c.request_check_length_limit, " ",
                    c.response_check_length_limit, " ", c.timeout, " ",
                    c.keepalive and "on" or "off", " ", c.keepalive_timeout)
        }
    }
--- response_body
request limit over 1 KB: rejected
response limit over 1 KB: rejected
zero request limit: rejected
1 KB limit: accepted
defaults: 1000 1000 10000 on 60000
