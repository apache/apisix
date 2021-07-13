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
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
              uri = "/uri",
              plugins = {
                ["traffic-split"] = {
                  rules = { {
                    match = { {
                      vars = { { "arg_name", "==", "jack" } }
                    } },
                    weighted_upstreams = { {
                      upstream = {
                        type = "roundrobin",
                        pass_host = "rewrite",
                        upstream_host = "test.com",
                        nodes = {
                          ["127.0.0.1:1981"] = 1
                        }
                      }
                    } }
                  } }
                }
              },
              upstream = {
                type = "roundrobin",
                nodes = {
                  ["127.0.0.1:1980"] = 1
                }
              }
            }
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                json.encode(data)
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



=== TEST 10: the upstream.type is `chash` and `key` is header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [=[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "name": "chash_test",
                                                "type": "chash",
                                                "hash_on": "header",
                                                "key": "custom_header",
                                                "nodes": {
                                                    "127.0.0.1:1981":1,
                                                    "127.0.0.1:1982":1
                                                }
                                            },
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
--- no_error_log
[error]



=== TEST 11: hit routes, hash_on custom header
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        local headers2 = {}
        headers["custom_header"] = "hello"
        headers2["custom_header"] = "world"
        for i = 1, 8, 2 do
            local _, _, body = t('/server_port', ngx.HTTP_GET, "", nil, headers2)
            local _, _, body2 = t('/server_port', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
            bodys[i+1] = body2
        end

        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body eval
qr/1981, 1982, 1981, 1982, 1981, 1982, 1981, 1982/
--- grep_error_log eval
qr/hash_on: header|chash_key: "hello"|chash_key: "world"/
--- grep_error_log_out
hash_on: header
chash_key: "world"
hash_on: header
chash_key: "hello"
hash_on: header
chash_key: "world"
hash_on: header
chash_key: "hello"
hash_on: header
chash_key: "world"
hash_on: header
chash_key: "hello"
hash_on: header
chash_key: "world"
hash_on: header
chash_key: "hello"



=== TEST 12: the plugin has multiple weighted_upstreams(upstream method)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/server_port",
                plugins = {
                    ["traffic-split"] = {
                    rules = { {
                        match = { {
                            vars = { { "arg_id", "==", "1" } }
                        } },
                        weighted_upstreams = { {
                            upstream = {
                                name = "upstream_A",
                                type = "roundrobin",
                                nodes = {
                                    ["127.0.0.1:1981"] = 1
                                }
                            },
                            weight = 1
                        } }
                    }, {
                        match = { {
                            vars = { { "arg_id", "==", "2" } }
                        } },
                        weighted_upstreams = { {
                            upstream = {
                                name = "upstream_B",
                                type = "roundrobin",
                                nodes = {
                                    ["127.0.0.1:1982"] = 1
                                }
                            },
                            weight = 1
                        } }
                    } }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: hit each upstream separately
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 9, 3 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            local _, _, body2 = t('/server_port?id=1', ngx.HTTP_GET)
            local _, _, body3 = t('/server_port?id=2', ngx.HTTP_GET)
            bodys[i] = body
            bodys[i+1] = body2
            bodys[i+2] = body3
        end

        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body eval
qr/1980, 1981, 1982, 1980, 1981, 1982, 1980, 1981, 1982/
--- no_error_log
[error]



=== TEST 14: the plugin has multiple weighted_upstreams and has a default routing weight in weighted_upstreams
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/server_port",
                plugins = {
                    ["traffic-split"] = {
                        rules = { {
                            match = { {
                            vars = { { "arg_id", "==", "1" } }
                            } },
                            weighted_upstreams = { {
                            upstream = {
                                name = "upstream_A",
                                type = "roundrobin",
                                nodes = {
                                    ["127.0.0.1:1981"] = 1
                                }
                            },
                            weight = 1
                            }, {
                            weight = 1
                            } }
                        }, {
                            match = { {
                            vars = { { "arg_id", "==", "2" } }
                            } },
                            weighted_upstreams = { {
                            upstream = {
                                name = "upstream_B",
                                type = "roundrobin",
                                nodes = {
                                    ["127.0.0.1:1982"] = 1
                                }
                            },
                            weight = 1
                            }, {
                            weight = 1
                            } }
                        } }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: every weighted_upstreams in the plugin is hit
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 8, 2 do
            local _, _, body = t('/server_port?id=1', ngx.HTTP_GET)
            local _, _, body2 = t('/server_port?id=2', ngx.HTTP_GET)
            bodys[i] = body
            bodys[i+1] = body2
        end

        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body eval
qr/1980, 1980, 1980, 1980, 1981, 1981, 1982, 1982/
--- no_error_log
[error]



=== TEST 16: set upstream(upstream_id: 1, upstream_id: 2) and add route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:1981": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream A"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            code, body = t('/apisix/admin/upstreams/2',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:1982": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream B"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [=[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_id","==","1"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream_id": 1,
                                            "weight": 1
                                        }
                                    ]
                                },
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_id","==","2"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream_id": 2,
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 17: hit each upstream separately
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 9, 3 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            local _, _, body2 = t('/server_port?id=1', ngx.HTTP_GET)
            local _, _, body3 = t('/server_port?id=2', ngx.HTTP_GET)
            bodys[i] = body
            bodys[i+1] = body2
            bodys[i+2] = body3
        end

        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body eval
qr/1980, 1981, 1982, 1980, 1981, 1982, 1980, 1981, 1982/
--- no_error_log
[error]



=== TEST 18: multi nodes with `node` mode to pass host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "localhost:1979": 1000,
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin",
                    "pass_host": "node"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [=[{
                    "uri": "/uri",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [["arg_id","==","1"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream_id": 1,
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
                                "127.0.0.1:1978": 1
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
--- skip_nginx: 5: < 1.19.0
--- response_body
passed



=== TEST 19: hit route
--- request
GET /uri?id=1
--- skip_nginx: 5: < 1.19.0
--- response_body eval
qr/host: 127.0.0.1/
--- error_log
proxy request to 127.0.0.1:1980
