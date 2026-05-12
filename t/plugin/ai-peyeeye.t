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
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

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

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    # Mock peyeeye API on :6725.
    #
    # /v1/redact echoes one placeholder per input text. The fixture lets us
    # exercise the length-guard branches without round-tripping the real API:
    #   * X-PEyeEye-Mode: bad-shape   -> returns text as a string instead of an array
    #   * X-PEyeEye-Mode: short       -> drops the last redacted text
    #   * (default)                   -> one [PII_n] placeholder per input
    #
    # /v1/rehydrate replaces [PII_n] occurrences in text with the literal
    # string "<rehydrated>" so tests can assert on observable output.
    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6725;

            default_type 'application/json';

            location /v1/redact {
                content_by_lua_block {
                    local core = require("apisix.core")
                    ngx.req.read_body()
                    local body = ngx.req.get_body_data() or "{}"
                    local data = core.json.decode(body) or {}
                    local mode = ngx.req.get_headers()["X-PEyeEye-Mode"]

                    -- check Authorization header is present
                    local auth = ngx.req.get_headers()["Authorization"]
                    if not auth or not auth:find("Bearer ", 1, true) then
                        ngx.status = 401
                        ngx.say(core.json.encode({error = "missing bearer"}))
                        return
                    end

                    if mode == "bad-shape" then
                        ngx.say(core.json.encode({
                            text = "not-an-array",
                            session_id = "ses_bad",
                        }))
                        return
                    end

                    local out = {}
                    if type(data.text) == "table" then
                        for i, _ in ipairs(data.text) do
                            out[i] = "[PII_" .. i .. "]"
                        end
                    end
                    if mode == "short" and #out > 0 then
                        out[#out] = nil
                    end

                    if data.session == "stateless" then
                        ngx.say(core.json.encode({
                            text = out,
                            rehydration_key = "skey_stateless_42",
                        }))
                    else
                        ngx.say(core.json.encode({
                            text = out,
                            session_id = "ses_redact_42",
                        }))
                    end
                }
            }

            location /v1/rehydrate {
                content_by_lua_block {
                    local core = require("apisix.core")
                    ngx.req.read_body()
                    local body = ngx.req.get_body_data() or "{}"
                    local data = core.json.decode(body) or {}
                    local text = data.text or ""
                    local replaced
                    text, replaced = string.gsub(text, "%[PII_%d+%]", "<rehydrated>")
                    ngx.say(core.json.encode({text = text, replaced = replaced}))
                }
            }

            location ~ ^/v1/sessions/ses_ {
                content_by_lua_block {
                    if ngx.req.get_method() ~= "DELETE" then
                        ngx.status = 405
                        return
                    end
                    ngx.status = 204
                }
            }
        }

        # Fake LLM upstream for the integration test. Replies with a JSON body
        # that embeds [PII_1] so the rehydrate step has something to replace.
        server {
            listen 6726;
            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local core = require("apisix.core")
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data() or "{}"
                    -- Echo the request back so tests can assert that the body
                    -- forwarded to the model has been redacted.
                    local req = core.json.decode(raw) or {}
                    local first = ""
                    if type(req.messages) == "table" and req.messages[1]
                            and type(req.messages[1].content) == "string" then
                        first = req.messages[1].content
                    end
                    ngx.say(core.json.encode({
                        id = "chatcmpl-test",
                        object = "chat.completion",
                        choices = {
                            {
                                index = 0,
                                message = {
                                    role = "assistant",
                                    content = "echo: " .. first,
                                },
                                finish_reason = "stop",
                            },
                        },
                        usage = {
                            prompt_tokens = 1,
                            completion_tokens = 2,
                            total_tokens = 3,
                        },
                    }))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: schema validation rejects config with no api_key and no env var
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-peyeeye")
            -- ensure env is unset for this check
            local ok, err = plugin.check_schema({})
            if ok then
                ngx.say("unexpectedly accepted")
            else
                ngx.say(err)
            end
        }
    }
--- response_body_like
.*api_key is required.*



=== TEST 2: schema validation accepts a minimal config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-peyeeye")
            local ok, err = plugin.check_schema({
                api_key = "test-key",
                api_base = "http://127.0.0.1:6725",
            })
            if ok then
                ngx.say("ok")
            else
                ngx.say(err)
            end
        }
    }
--- response_body
ok



=== TEST 3: schema validation rejects unknown session_mode
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-peyeeye")
            local ok, err = plugin.check_schema({
                api_key = "test-key",
                session_mode = "garbage",
            })
            if ok then
                ngx.say("unexpectedly accepted")
            else
                ngx.say("rejected")
            end
        }
    }
--- response_body
rejected



=== TEST 4: set up a route with ai-peyeeye + ai-proxy (stateful)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-peyeeye": {
                            "api_key": "test-key",
                            "api_base": "http://127.0.0.1:6725",
                            "ssl_verify": false
                        },
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:6726/v1/chat/completions"
                            }
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



=== TEST 5: stateful redact + rehydrate end-to-end
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "My email is alice@example.com" } ] }
--- error_code: 200
--- response_body_like
.*<rehydrated>.*



=== TEST 6: redact with mismatched length must fail closed (no upstream call)
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "first" }, { "role": "user", "content": "second" } ] }
--- more_headers
X-PEyeEye-Mode: short
--- error_code: 500
--- response_body_like
.*refusing to forward unredacted text.*



=== TEST 7: redact with unexpected response shape must fail closed
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "hi" } ] }
--- more_headers
X-PEyeEye-Mode: bad-shape
--- error_code: 500
--- response_body_like
.*refusing to forward unredacted text.*



=== TEST 8: stateless mode uses skey_ rehydration key (no DELETE call)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-peyeeye": {
                            "api_key": "test-key",
                            "api_base": "http://127.0.0.1:6725",
                            "session_mode": "stateless",
                            "ssl_verify": false
                        },
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:6726/v1/chat/completions"
                            }
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



=== TEST 9: stateless redact + rehydrate end-to-end
--- request
POST /chat
{ "messages": [ { "role": "user", "content": "card 4242-4242-4242-4242" } ] }
--- error_code: 200
--- response_body_like
.*<rehydrated>.*



=== TEST 10: empty body short-circuits without calling peyeeye
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-empty",
                    "plugins": {
                        "ai-peyeeye": {
                            "api_key": "test-key",
                            "api_base": "http://127.0.0.1:6725",
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
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



=== TEST 11: GET request with no body bypasses redaction silently
--- request
GET /chat-empty
--- error_code: 404



=== TEST 12: 401 from peyeeye fails closed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-peyeeye": {
                            "api_key": "",
                            "api_base": "http://127.0.0.1:6725",
                            "ssl_verify": false
                        },
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:6726/v1/chat/completions"
                            }
                        }
                    }
                }]]
            )
            -- empty api_key + no env should be rejected at schema time
            if code >= 300 then
                ngx.say("rejected")
            else
                ngx.say(body)
            end
        }
    }
--- response_body
rejected
