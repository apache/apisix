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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->error_log && !defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: check routes conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/routes/1',
                ngx.HTTP_POST,
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
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 2: route conf don't write etcd
--- request
GET /index.html
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 3: check routes conf: wrong method
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/check_conf/routes/1',
                ngx.HTTP_PUT,
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
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 404
--- response_body
{"error_msg":"not found"}



=== TEST 4: check routes conf: missing uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/check_conf/routes/1',
                ngx.HTTP_POST,
                [[{
                    "methods": ["GET"],
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
{"error_msg":"invalid configuration: allOf 1 failed: value should match only one schema, but matches none"}



=== TEST 5: check consumer conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/consumers',
                ngx.HTTP_POST,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 6: check global_rules conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/global_rules/1',
                ngx.HTTP_POST,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 7: check plugin_configs conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/plugin_configs/1',
                ngx.HTTP_POST,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 8: check plugin_metadata conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/plugin_metadata/example-plugin',
                ngx.HTTP_POST,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 9: check plugin_metadata conf: missing plugin name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/check_conf/plugin_metadata',
                ngx.HTTP_POST,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"missing plugin name"}



=== TEST 10: check plugins conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/plugins',
                ngx.HTTP_POST,
                [[{
                    "limit-count": {
                        "count": 2,
                        "time_window": 60,
                        "rejected_code": 503,
                        "key": "remote_addr"
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 11: check protos conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/protos/1',
                ngx.HTTP_POST,
                [[{
                    "content" : "syntax = \"proto3\";
                    package helloworld;
                    service Greeter {
                        rpc SayHello (HelloRequest) returns (HelloReply) {}
                    }
                    message HelloRequest {
                        string name = 1;
                    }
                    message HelloReply {
                        string message = 1;
                    }"
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 12: check services conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/services/1',
                ngx.HTTP_POST,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "enable_websocket": true,
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 13: check ssls conf
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
            }
            local code = t.test('/apisix/admin/check_conf/ssls/1',
                ngx.HTTP_POST,
                core.json.encode(data)
                )

            ngx.status = code
        }
    }



=== TEST 14: check upstream conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/upstreams/1',
                ngx.HTTP_POST,
                [[{
                    "id": "1",
                    "retries": 1,
                    "timeout": {
                        "connect":15,
                        "send":15,
                        "read":15
                    },
                    "nodes": {"httpbin.org:80": 100},
                    "type":"roundrobin",
                    "hash_on": "vars",
                    "key": "",
                    "name": "upstream-xxx",
                    "desc": "hello world",
                    "scheme": "http"
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 15: check stream_routes conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/check_conf/stream_routes/1',
                ngx.HTTP_POST,
                [[{
                    "server_addr": "127.0.0.1",
                    "server_port": 2000,
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            ngx.status = code
        }
    }



=== TEST 16: exclude schema resources
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/check_conf/schema',
                ngx.HTTP_POST,
                [[{}]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 404
--- response_body
{"error_msg":"not found"}



=== TEST 17: not exits resource
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/check_conf/fake',
                ngx.HTTP_POST,
                [[{}]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 404
--- response_body
{"error_msg":"not found"}
