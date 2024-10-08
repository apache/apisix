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

=== TEST 1: sanity
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
                        "ai-prompt-template": {
                            "templates":[
                                {
                                    "name": "programming question",
                                    "template": {
                                        "model": "some model",
                                        "messages": [
                                            { "role": "system", "content": "You are a {{ language }} programmer." },
                                            { "role": "user", "content": "Write a {{ program_name }} program." }
                                        ]
                                    }
                                },
                                {
                                    "name": "level of detail",
                                    "template": {
                                        "model": "some model",
                                        "messages": [
                                            { "role": "user", "content": "Explain about {{ topic }} in {{ level }}." }
                                        ]
                                    }
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



=== TEST 2: no templates
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
                        "ai-prompt-template": {
                            "templates":[]
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
--- response_body eval
qr/.*property \\"templates\\" validation failed: expect array to have at least 1 items.*/



=== TEST 3: test template insertion
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "template_name": "programming question",
                        "language": "python",
                        "program_name": "quick sort"
                    }]],
                    [[{
                        "model": "some model",
                        "messages": [
                            { "role": "system", "content": "You are a python programmer." },
                            { "role": "user", "content": "Write a quick sort program." }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 4: multiple templates
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
                        "ai-prompt-template": {
                            "templates":[
                                {
                                    "name": "programming question",
                                    "template": {
                                        "model": "some model",
                                        "messages": [
                                            { "role": "system", "content": "You are a {{ language }} programmer." },
                                            { "role": "user", "content": "Write a {{ program_name }} program." }
                                        ]
                                    }
                                },
                                {
                                    "name": "level of detail",
                                    "template": {
                                        "model": "some model",
                                        "messages": [
                                            { "role": "user", "content": "Explain about {{ topic }} in {{ level }}." }
                                        ]
                                    }
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



=== TEST 5: test second template
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "template_name": "level of detail",
                        "topic": "psychology",
                        "level": "brief"
                    }]],
                    [[{
                        "model": "some model",
                        "messages": [
                            { "role": "user", "content": "Explain about psychology in brief." }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 6: missing template items
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "template_name": "level of detail",
                        "topic-missing": "psychology",
                        "level-missing": "brief"
                    }]],
                    [[{
                        "model": "some model",
                        "messages": [
                            { "role": "user", "content": "Explain about  in ." }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: request body contains non-existent template
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local code, body, actual_resp = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "template_name": "random",
                    "some-key": "some-value"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- error_code: 400
--- response_body eval
qr/.*template: random not configured.*/



=== TEST 8: request body contains non-existent template
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local code, body, actual_resp = t('/echo',
                ngx.HTTP_POST,
                [[{
                    "missing-template-name": "haha"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- error_code: 400
--- response_body eval
qr/.*template name is missing in request.*/



=== TEST 9: (cache test) same template name in different routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i = 1, 5, 1 do
                local code = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri": "/]] .. i .. [[",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ai-prompt-template": {
                                "templates":[
                                    {
                                        "name": "same name",
                                        "template": {
                                            "model": "some model",
                                            "messages": [
                                                { "role": "system", "content": "Field: {{ field }} in route]] .. i .. [[." }
                                            ]
                                        }
                                    }
                                ]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        }
                    }]]
                )

                if code >= 300 then
                    ngx.status = code
                    ngx.say("failed")
                    return
                end
            end

            for i = 1, 5, 1 do
                local code, body = t('/' .. i,
                    ngx.HTTP_POST,
                    [[{
                        "template_name": "same name",
                        "field": "foo"
                    }]],
                    [[{
                        "model": "some model",
                        "messages": [
                            { "role": "system", "content": "Field: foo in route]] .. i .. [[." }
                        ]
                    }]]
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.status = 200
            ngx.say("passed")
        }
    }

--- response_body
passed
