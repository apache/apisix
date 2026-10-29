
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

=== TEST 1: setup embeddings guard route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {"127.0.0.1:1980": 1}
                },
                "plugins": {
                    "ai-prompt-guard": {"deny_patterns": ["badword"]}
                }
            }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: reject a denied first batch item
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["badword", "safe"]}
--- error_code: 400
--- response_body
{"message":"Request contains prohibited content"}



=== TEST 3: reject a denied last batch item
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["safe", "badword"]}
--- error_code: 400
--- response_body
{"message":"Request contains prohibited content"}



=== TEST 4: forward a safe string batch
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["safe", "other"]}
--- error_code: 200
--- response_body
hello world



=== TEST 5: forward token IDs without text inspection
--- request
POST /hello
{"model": "text-embedding-3-small", "input": [123, 456]}
--- error_code: 200
--- response_body
hello world



=== TEST 6: forward intentionally unselected system content
--- request
POST /hello
{"messages":[{"role":"system","content":"badword"}]}
--- error_code: 200
--- response_body
hello world



=== TEST 7: enable strict options
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {"127.0.0.1:1980": 1}
                },
                "plugins": {
                    "ai-prompt-guard": {
                        "deny_patterns": ["badword"],
                        "match_all_roles": true,
                        "match_all_conversation_history": true,
                        "fail_mode": "error"
                    }
                }
            }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: reject the first denied item with strict options
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["badword", "safe"]}
--- error_code: 400
--- response_body
{"message":"Request contains prohibited content"}



=== TEST 9: forward safe batch with strict options
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["safe", "other"]}
--- error_code: 200
--- response_body
hello world



=== TEST 10: setup allow and deny patterns
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {"127.0.0.1:1980": 1}
                },
                "plugins": {
                    "ai-prompt-guard": {
                        "allow_patterns": ["goodword"],
                        "deny_patterns": ["badword"]
                    }
                }
            }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: allow pattern can match the first batch item
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["goodword", "safe"]}
--- error_code: 200
--- response_body
hello world



=== TEST 12: reject batch without an allow match
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["safe", "other"]}
--- error_code: 400
--- response_body
{"message":"Request doesn't match allow patterns"}



=== TEST 13: deny match rejects an otherwise allowed batch
--- request
POST /hello
{"model": "text-embedding-3-small", "input": ["goodword", "badword"]}
--- error_code: 400
--- response_body
{"message":"Request contains prohibited content"}



=== TEST 14: embeddings adapter normalizes text inputs without changing the request
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local proto = require("apisix.plugins.ai-protocols.openai-embeddings")
            local cases = {
                {input = "hello", expected = {"hello"}},
                {input = {"first", "last"}, expected = {"first", "last"}},
                {input = {"", "last"}, expected = {"", "last"}},
                {input = {123, 456}, expected = {}},
                {input = {{123}, {456}}, expected = {}},
                {input = {}, expected = {}},
            }
            for _, case in ipairs(cases) do
                local body = {input = case.input}
                local before = core.json.encode(body)
                local messages = proto.get_messages(body)
                assert(#messages == #case.expected)
                for i, text in ipairs(case.expected) do
                    assert(messages[i].role == "user")
                    assert(messages[i].content == text)
                end
                assert(core.json.encode(body) == before)
            end
            assert(#proto.get_messages(nil) == 0)
            ngx.say("passed")
        }
    }
--- response_body
passed
