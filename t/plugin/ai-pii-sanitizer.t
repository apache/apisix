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

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: invalid custom regex should fail schema check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "custom_patterns": [
                                { "name": "broken", "pattern": "(unclosed" }
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
--- response_body eval
qr/.*failed to check the configuration of plugin ai-pii-sanitizer.*/
--- error_code: 400



=== TEST 2: unknown category name should fail schema check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "categories": ["not_a_real_category"]
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
--- response_body eval
qr/.*unknown built-in category.*/
--- error_code: 400



=== TEST 3: configure email-only masking on input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "direction": "input",
                            "categories": ["email"]
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



=== TEST 4: email is masked in the outgoing request body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "email alice@acme.com with the bill" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "email [EMAIL_0] with the bill" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 5: stable-per-value placeholders collapse duplicates
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "a@x.com and b@x.com and a@x.com again" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "[EMAIL_0] and [EMAIL_1] and [EMAIL_0] again" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 6: configure credit_card with Luhn gating
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "categories": ["credit_card"]
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



=== TEST 7: Luhn-valid card is masked
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- 4532015112830366 is a known Luhn-valid Visa test number
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "card 4532015112830366 expires soon" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "card [CREDIT_CARD_0] expires soon" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: Luhn-invalid 16-digit string is NOT masked
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- 1234567890123456 fails Luhn
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "order 1234567890123456 today" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "order 1234567890123456 today" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 9: custom pattern with replace_with swaps the literal
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "categories": [],
                            "custom_patterns": [
                                {
                                    "name": "emp_id",
                                    "pattern": "EMP-\\d{6}",
                                    "replace_with": "[EMP_ID]"
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



=== TEST 10: custom pattern rewrites the outgoing body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "escalate to EMP-987654 please" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "escalate to [EMP_ID] please" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 11: allowlist literal is left alone even when it looks like PII
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "categories": ["email"],
                            "allowlist": ["support@company.com"]
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



=== TEST 12: allowlisted email passes through, other email masked
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "forward to support@company.com and cc alice@acme.com" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "forward to support@company.com and cc [EMAIL_0]" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 13: zero-width obfuscation is normalized before regex scan
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- ali​ce@acme.com — zero-width space between i and c
            local body_raw = '{"messages":[{"role":"user","content":"ali​ce@acme.com"}]}'
            local expected = '{"messages":[{"role":"user","content":"[EMAIL_0]"}]}'
            local code, body, actual = t('/echo', ngx.HTTP_POST, body_raw, expected)
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: block action returns configured status + body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "direction": "input",
                            "action": "block",
                            "categories": ["email"],
                            "on_block": {
                                "status": 403,
                                "body": "PII detected, blocked"
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



=== TEST 15: block returns 403 on email in input
--- request
POST /echo
{
    "messages": [
        { "role": "user", "content": "ping alice@acme.com" }
    ]
}
--- error_code: 403
--- response_body_like
.*PII detected, blocked.*



=== TEST 16: direction=output leaves input body alone
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "direction": "output",
                            "categories": ["email"]
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



=== TEST 17: direction=output passes input through unchanged
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "mail alice@acme.com please" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "user", "content": "mail alice@acme.com please" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: preamble is injected when restore_on_response=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "direction": "input",
                            "categories": ["email"],
                            "restore_on_response": true,
                            "preamble": {
                                "enable": true,
                                "content": "PREAMBLE-TEST"
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



=== TEST 19: preamble prepended as a system message and PII masked
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "user", "content": "mail alice@acme.com" }
                    ]
                }]],
                [[{
                    "messages": [
                        { "role": "system", "content": "PREAMBLE-TEST" },
                        { "role": "user", "content": "mail [EMAIL_0]" }
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: log_detections emits category hit log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-pii-sanitizer": {
                            "direction": "input",
                            "categories": ["email"],
                            "log_detections": true
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



=== TEST 21: detection log line is written, payload is NOT (log_payload default false)
--- request
POST /echo
{
    "messages": [
        { "role": "user", "content": "alice@acme.com" }
    ]
}
--- error_log
ai-pii-sanitizer input hits: email=1
--- no_error_log
[error]
[alert]
alice@acme.com
