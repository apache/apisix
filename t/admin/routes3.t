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

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: list empty resources
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/routes',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"get","count":0,"node":{"dir":true,"key":"/apisix/routes","nodes":{}}}



=== TEST 2: remote_addr: 127.0.0.1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.1",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/index.html"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 3: remote_addr: 127.0.0.1/24
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.0/24",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.0/24",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/index.html"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 4: remote_addr: 127.0.0.33333
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.33333",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"remote_addr\" validation failed: object matches none of the requireds"}



=== TEST 5: all method
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST", "PUT", "DELETE", "PATCH",
                                    "HEAD", "OPTIONS", "CONNECT", "TRACE"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: patch route(new uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")

            local id = 1
            local res = assert(etcd.get('/routes/' .. id))
            local prev_create_time = res.body.node.value.create_time
            local prev_update_time = res.body.node.value.update_time
            ngx.sleep(1)

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "uri": "/patch_test"
                }]],
                [[{
                    "node": {
                        "value": {
                            "uri": "/patch_test"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/routes/' .. id))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- response_body
passed



=== TEST 7: patch route(multi)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": null,
                            "127.0.0.2:8080": 1
                        }
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/patch_test",
                            "desc": "new route",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.2:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: patch route(new methods)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET", "DELETE", "PATCH", "POST", "PUT"]
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": ["GET", "DELETE", "PATCH", "POST", "PUT"]
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: patch route(minus methods)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET", "POST"]
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": ["GET", "POST"]
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: patch route(new methods - sub path way)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/methods',
                ngx.HTTP_PATCH,
                '["POST"]',
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "POST"
                            ]
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: patch route(new uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/uri',
                ngx.HTTP_PATCH,
                '"/patch_uri_test"',
                [[{
                    "node": {
                        "value": {
                            "uri": "/patch_uri_test"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: patch route(whole)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/index.html",
                            "desc": "new route",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: multiple hosts
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "hosts": ["foo.com", "*.bar.com"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "hosts": ["foo.com", "*.bar.com"]
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: enable hosts and host together
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "host": "xxx.com",
                    "hosts": ["foo.com", "*.bar.com"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"only one of host or hosts is allowed"}



=== TEST 15: multiple remote_addrs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "remote_addrs": ["127.0.0.1", "192.0.0.1/8", "::1", "fe80::/32"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addrs": ["127.0.0.1", "192.0.0.1/8", "::1", "fe80::/32"]
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: multiple vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "vars": [["arg_name", "==", "json"], ["arg_age", ">", 18]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]=],
                [=[{
                    "node": {
                        "value": {
                            "vars": [["arg_name", "==", "json"], ["arg_age", ">", 18]]
                        }
                    }
                }]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 17: filter function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "filter_func": "function(vars) return vars.arg_name == 'json' end",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=],
                [=[{
                    "node": {
                        "value": {
                            "filter_func": "function(vars) return vars.arg_name == 'json' end"
                        }
                    }
                }]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: filter function (invalid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "filter_func": "function(vars) ",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to load 'filter_func' string: [string \"return function(vars) \"]:1: 'end' expected near '<eof>'"}



=== TEST 19: Support for multiple URIs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uris": ["/index.html","/index2.html"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed
