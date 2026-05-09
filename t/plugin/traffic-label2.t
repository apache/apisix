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

=== TEST 1: use traffic-label plugin with proxy-rewrite plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/echo"
                            },
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
                        "uri": "/*"
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



=== TEST 2: trigger workflow
--- request
GET /echo_not_exist
--- more_headers
X-server-id: 100
--- response_headers
X-Server-id: 100



=== TEST 3: trigger workflow
--- request
GET /echo_not_exist?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 4: trigger workflow
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 5: trigger workflow
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 6: If there is no match condition in rule, all requests are matched by default
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



=== TEST 7: match the condition
--- request
GET /echo
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 100



=== TEST 8: multiple headers
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
                                                    "X-request-id": "id2"
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



=== TEST 9: trigger traffic-label
--- pipelined_requests eval
[
    "GET /echo",
    "GET /echo",
]
--- more_headers
X-server-id: 200
X-request-id: id1
--- response_headers eval
[
    "X-Server-id: 100",
    "X-request-id: id2"
]



=== TEST 10: multiple actions
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
                                                "weight": 1
                                            },
                                            {
                                                "set_headers": {
                                                    "X-server-id": 200
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



=== TEST 11: trigger traffic-label
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"

            local resp_arr = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(resp_arr, res.headers["X-Server-id"])
            end

            table.sort(resp_arr, cmd)

            ngx.say(require("toolkit.json").encode(resp_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
["100","200"]



=== TEST 12: no action
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



=== TEST 13: match the condition
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 200
--- response_headers
X-Server-id: 200



=== TEST 14: multiple rules
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
                                            ["arg_foo", "==", "water"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 200
                                                }
                                            }
                                        ]
                                    },
                                    {
                                        "match": [
                                            ["arg_foo", "==", "bar"]
                                        ],
                                        "actions": [
                                            {
                                                "set_headers": {
                                                    "X-server-id": 300
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



=== TEST 15: match one condition
--- request
GET /echo?foo=water
--- more_headers
X-server-id: 100
--- response_headers
X-Server-id: 200



=== TEST 16: match one condition
--- request
GET /echo?foo=bar
--- more_headers
X-server-id: 100
--- response_headers
X-Server-id: 300



=== TEST 17: set plugin without configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
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
qr/property \\"rules\\" is required/



=== TEST 18: set plugin with empty rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "traffic-label": {
                                "rules": []
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
qr/expect array to have at least 1 items/
