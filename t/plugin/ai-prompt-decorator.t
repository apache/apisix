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

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sanity: configure prepend only
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
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "some content"
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



=== TEST 2: test prepend
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "some content" },
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
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



=== TEST 3: sanity: configure append only
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
                        "ai-prompt-decorator": {
                            "append":[
                                {
                                    "role": "system",
                                    "content": "some content"
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



=== TEST 4: test append
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" },
                            { "role": "system", "content": "some content" }
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



=== TEST 5: sanity: configure append and prepend both
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
                        "ai-prompt-decorator": {
                            "append":[
                                {
                                    "role": "system",
                                    "content": "some append"
                                }
                            ],
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "some prepend"
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



=== TEST 6: test append
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "some prepend" },
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" },
                            { "role": "system", "content": "some append" }
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



=== TEST 7: sanity: configure neither append nor prepend should fail
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
                        "ai-prompt-decorator": {
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
--- response_body_eval
qr/.*failed to check the configuration of plugin ai-prompt-decorator err.*/
--- error_code: 400
