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
add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = <<_EOC_;
plugins:
    - traffic-label
    - proxy-rewrite
_EOC_

    if (!$block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();


__DATA__

=== TEST 1: Use unsupported action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["uri", "==", "/echo"]
                                        ],
                                        "actions":[
                                            {
                                                "add_headers": {
                                                    "X-server-id": 100
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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
qr/not supported action: add_headers/



=== TEST 2: Only one operator are supported in the same level
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            "AND",
                                            "OR",
                                            ["uri", "==", "/echo"],
                                            ["arg_foo", "==", "bar"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 500
--- error_log eval
qr/bad argument/



=== TEST 3: use traffic-label plugin to override one req header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["arg_foo", "==", "bar"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 4: trigger traffic-label, mismatch
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 5: trigger traffic-label
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 6: use traffic-label plugin to add a new req header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["uri", "==", "/echo"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100,
                                                    "resp-X-content-type": "json"
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 7: trigger traffic-label
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100
X-content-type: json



=== TEST 8: AND condition in match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["uri", "==", "/echo"],
                                            ["arg_foo", "==", "bar"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 9: mismatch the condition
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 10: match the condition
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 11: OR condition in match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            "OR",
                                            ["arg_foo", "==", "bar"],
                                            ["uri", "==", "/echo"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 12: match the condition
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 13: wrong weight in rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["uri", "==", "/echo"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                },
                                                "weight": 0.2
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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
qr/property \\"weight\\" validation failed/



=== TEST 14: ipmatch operator, mismatch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["remote_addr", "ipmatch", "127.0.0.2"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                },
                                                "weight": 1
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 15: trigger traffic-label
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 16: ipmatch operator, match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            ["remote_addr", "ipmatch", "127.0.0.1"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                },
                                                "weight": 1
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 17: trigger traffic-label
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 18: nested expr
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": [
                                    {
                                        "match": [
                                            "AND",
                                            ["remote_addr", "ipmatch", "127.0.0.1"],
                                            [
                                                "AND",
                                                ["uri", "==", "/echo"],
                                                ["arg_foo", "==", "bar"]
                                            ]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 100
                                                },
                                                "weight": 1
                                            }
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 19: trigger traffic-label, mismatch
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 20: trigger traffic-label, match
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100
