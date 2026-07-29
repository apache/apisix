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

    # Mock AWS Comprehend detectToxicContent: looks up the extracted text
    # (TextSegments[1].Text) in the canned responses fixture.
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
                    local result = body.TextSegments[1].Text
                    local final_response = responses[result] or "invalid"

                    if final_response == "invalid" then
                        ngx.status = 500
                    end
                    ngx.say(json.encode(final_response))
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
