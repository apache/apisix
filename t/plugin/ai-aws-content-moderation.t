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

=== TEST 1: sanity
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



=== TEST 2: toxic request should fail
--- request
POST /echo
{"messages":[{"role":"user","content":"toxic"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds toxicity threshold



=== TEST 3: good request should pass
--- request
POST /echo
{"messages":[{"role":"user","content":"good_request"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 4: profanity filter
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
                            "moderation_categories": {
                                "PROFANITY": 0.5
                            }
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



=== TEST 5: profane request should fail
--- request
POST /echo
{"messages":[{"role":"user","content":"profane"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds PROFANITY threshold



=== TEST 6: very profane request should also fail
--- request
POST /echo
{"messages":[{"role":"user","content":"very_profane"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds PROFANITY threshold



=== TEST 7: good_request should pass
--- request
POST /echo
{"messages":[{"role":"user","content":"good_request"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 8: set profanity = 0.7 (allow profane request but disallow very_profane)
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
                            "moderation_categories": {
                                "PROFANITY": 0.7
                            }
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



=== TEST 9: profane request should pass profanity check but fail toxicity check
--- request
POST /echo
{"messages":[{"role":"user","content":"profane"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds toxicity threshold



=== TEST 10: profane_but_not_toxic request should pass
--- request
POST /echo
{"messages":[{"role":"user","content":"profane_but_not_toxic"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 11: but very profane request will fail
--- request
POST /echo
{"messages":[{"role":"user","content":"very_profane"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds PROFANITY threshold



=== TEST 12: good_request should pass
--- request
POST /echo
{"messages":[{"role":"user","content":"good_request"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 13: setup route with default fail_mode (skip)
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



=== TEST 14: non-JSON (multipart) request passes through by default (skip) to upstream
--- request
POST /echo
name=alice&action=upload
--- more_headers
Content-Type: multipart/form-data
--- error_code: 200
--- response_body chomp
name=alice&action=upload



=== TEST 15: setup route with fail_mode=error
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



=== TEST 16: non-JSON request is rejected when fail_mode=error
--- request
POST /echo
name=alice&action=upload
--- more_headers
Content-Type: multipart/form-data
--- error_code: 400
--- response_body eval
qr/only application\/json is supported/



=== TEST 17: only the decoded LLM content is moderated, not the raw JSON envelope
--- request
POST /echo
{"model":"gpt-4","messages":[{"role":"user","content":"toxic"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds toxicity threshold



=== TEST 18: non-AI JSON body is rejected when fail_mode=error
--- request
POST /echo
{"foo":"bar"}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body eval
qr/no supported AI protocol for the request/



=== TEST 19: malformed JSON body is rejected when fail_mode=error
--- request
POST /echo
not-json
--- more_headers
Content-Type: application/json
--- error_code: 400



=== TEST 20: setup route with default fail_mode (skip)
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



=== TEST 21: non-AI JSON body passes through unchecked when fail_mode=skip
--- request
POST /echo
{"foo":"bar"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body chomp
{"foo":"bar"}



=== TEST 22: setup route with default moderation
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



=== TEST 23: content smuggled via JSON unicode escapes is decoded before moderation
--- request
POST /echo
{"messages":[{"role":"user","content":"\u0074\u006f\u0078\u0069\u0063"}]}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body chomp
request body exceeds toxicity threshold
