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
master_on();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: vars rule with ! (set)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                ["!AND",
                                                 ["arg_name", "==", "jack"],
                                                 ["arg_age", "!", "<", "18"]
                                                ]
                                            ]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":1}},
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]=]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: vars rule with ! (hit)
--- request
GET /server_port?name=jack&age=17
--- response_body chomp
1981



=== TEST 3: vars rule with ! (miss)
--- request
GET /server_port?name=jack&age=18
--- response_body chomp
1980



=== TEST 4: the upstream node is IP and pass_host is `pass`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/uri",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "type": "roundrobin",
                                                "pass_host": "pass",
                                                "nodes": {
                                                    "127.0.0.1:1981":1
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]=]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: upstream_host is `127.0.0.1`
--- request
GET /uri?name=jack
--- more_headers
host: 127.0.0.1
--- response_body
uri: /uri
host: 127.0.0.1
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 6: the upstream node is IP and pass_host is `rewrite`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [=[{
                    "uri": "/uri",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "type": "roundrobin",
                                                "pass_host": "rewrite",
                                                "upstream_host": "test.com",
                                                "nodes": {
                                                    "127.0.0.1:1981":1
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]=]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: upstream_host is test.com
--- request
GET /uri?name=jack
--- response_body
uri: /uri
host: test.com
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 8: the upstream node is IP and pass_host is `node`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [=[{
                    "uri": "/uri",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "type": "roundrobin",
                                                "pass_host": "node",
                                                "nodes": {
                                                    "localhost:1981":1
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]=]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: upstream_host is localhost
--- request
GET /uri?name=jack
--- more_headers
host: 127.0.0.1
--- response_body
uri: /uri
host: localhost
x-real-ip: 127.0.0.1
--- no_error_log
[error]
