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
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->response_body && !$block->response_body_like) {
        $block->set_value("response_body", "passed\n");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: PUT
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/multitier_network',
                ngx.HTTP_PUT,
                [[{
                    "desc": "this is test",
                    "selector": "apisix.multitier_network.selector",
                    "selector_conf": {
                        "blah": [],
                        "foo": "bar"
                    },
                    "gateways": {
                        "en": {
                            "http": {
                                "nodes": [
                                    {"host":"127.0.0.1", "port":80, "weight": 1},
                                    {"host":"x.com", "port":80, "weight": 1}
                                ]
                            }
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "desc": "this is test",
                            "selector": "apisix.multitier_network.selector",
                            "selector_conf": {
                                "blah": [],
                                "foo": "bar"
                            },
                            "gateways": {
                                "en": {
                                    "http": {
                                        "nodes": [
                                            {"host":"127.0.0.1", "port":80, "weight": 1},
                                            {"host":"x.com", "port":80, "weight": 1}
                                        ]
                                    }
                                }
                            }
                        },
                        "key": "/apisix/multitier_network"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/multitier_network'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }



=== TEST 2: GET
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/multitier_network',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "value": {
                            "desc": "this is test",
                            "selector": "apisix.multitier_network.selector",
                            "selector_conf": {
                                "blah": [],
                                "foo": "bar"
                            },
                            "gateways": {
                                "en": {
                                    "http": {
                                        "nodes": [
                                            {"host":"127.0.0.1", "port":80, "weight": 1},
                                            {"host":"x.com", "port":80, "weight": 1}
                                        ]
                                    }
                                }
                            }
                        },
                        "key": "/apisix/multitier_network"
                    },
                    "action": "get"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }



=== TEST 3: DELETE
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/multitier_network',
                ngx.HTTP_DELETE,
                nil,
                [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed



=== TEST 4: DELETE (not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/multitier_network',
                ngx.HTTP_DELETE,
                nil,
                [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code)
        }
    }
--- response_body
[delete] code: 404



=== TEST 5: GET (not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/multitier_network',
                ngx.HTTP_GET
                )
            ngx.say("[get] code: ", code)
        }
    }
--- response_body
[get] code: 404



=== TEST 6: validate (bad scheme)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/multitier_network',
                ngx.HTTP_PUT,
                [[{
                    "desc": "this is test",
                    "selector": "apisix.multitier_network.selector",
                    "selector_conf": {
                        "blah": [],
                        "foo": "bar"
                    },
                    "gateways": {
                        "en": {
                            "htts": {
                                "nodes": [
                                    {"host":"127.0.0.1", "port":80, "weight": 1},
                                    {"host":"x.com", "port":80, "weight": 1}
                                ]
                            }
                        }
                    }
                }]])

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/additional properties forbidden, found htts/



=== TEST 7: validate (not gateways)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/multitier_network',
                ngx.HTTP_PUT,
                [[{
                    "desc": "this is test",
                    "selector": "apisix.multitier_network.selector",
                    "selector_conf": {
                        "blah": [],
                        "foo": "bar"
                    }
                }]])

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/property \\"gateways\\" is required"/
