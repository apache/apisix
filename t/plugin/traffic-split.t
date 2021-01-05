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

run_tests;

__DATA__

=== TEST 1: schema validation passed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.traffic-split")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                vars = {
                                    {"arg_name", "==", "jack"},
                                    {"arg_age", "!", "<", "16"}
                                }
                            },
                             {
                                vars = {
                                    {"arg_name", "==", "rose"},
                                    {"arg_age", "!", ">", "32"}
                                }
                            }
                        },
                        weighted_upstreams = {
                            {
                                upstream = {
                                    name = "upstream_A",
                                    type = "roundrobin",
                                    nodes = {["127.0.0.1:1981"]=2},
                                    timeout = {connect = 15, send = 15, read = 15}
                                },
                                weight = 2
                            },
                            {
                                upstream = {
                                    name = "upstream_B",
                                    type = "roundrobin",
                                    nodes = {["127.0.0.1:1982"]=2},
                                    timeout = {connect = 15, send = 15, read = 15}
                                },
                                weight = 2
                            },
                            {
                                weight = 1
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: schema validation passed, and `match` configuration is missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.traffic-split")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        weighted_upstreams = {
                            {
                                upstream = {
                                    name = "upstream_A",
                                    type = "roundrobin",
                                    nodes = {["127.0.0.1:1981"]=2},
                                    timeout = {connect = 15, send = 15, read = 15}
                                },
                                weight = 2
                            },
                            {
                                weight = 1
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 3: schema validation failed, `vars` expression operator type is wrong
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.traffic-split")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                vars = {
                                    {"arg_name", 123, "jack"}
                                }
                            }
                        },
                        weighted_upstreams = {
                            {
                                upstream = {
                                    name = "upstream_A",
                                    type = "roundrobin",
                                    nodes = {["127.0.0.1:1981"]=2},
                                    timeout = {connect = 15, send = 15, read = 15}
                                },
                                weight = 2
                            },
                            {
                                weight = 1
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body eval
qr/property "rules" validation failed:.* failed to validate item 2: wrong type: expected string, got number/
--- no_error_log
[error]



=== TEST 4: missing `rules` configuration, the upstream of the default `route` takes effect
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {}
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: the upstream of the default `route` takes effect
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1980, 1980, 1980, 1980
--- no_error_log
[error]



=== TEST 6: when `weighted_upstreams` is empty, the upstream of `route` is used by default
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                             "rules": [
                                {
                                    "weighted_upstreams": [{}]
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
                }]]
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



=== TEST 7: the upstream of the default `route` takes effect
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1980, 1980, 1980, 1980
--- no_error_log
[error]



=== TEST 8: single `vars` expression and single plugin `upstream`, and the upstream traffic on `route` accounts for 1/3
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
                                            "vars": [["arg_name", "==", "jack"],["arg_age", "!","<", "16"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                           "upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":2}, "timeout": {"connect": 15, "send": 15, "read": 15}},
                                            "weight": 2
                                        },
                                        {
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



=== TEST 9: expression validation failed, return to the default `route` upstream port `1980`
--- request
GET /server_port?name=jack&age=14
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 10: the expression passes and initiated multiple requests, the upstream traffic of `route` accounts for 1/3, and the upstream traffic of plugins accounts for 2/3
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port?name=jack&age=16', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1981, 1981, 1981, 1981
--- no_error_log
[error]



=== TEST 11: Multiple vars rules and multiple plugin upstream
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
                                        {"vars": [["arg_name", "==", "jack"], ["arg_age", "~~", "^[1-9]{1,2}"]]},
                                        {"vars": [["arg_name2", "in", ["jack", "rose"]], ["arg_age2", "!", "<", 18]]}
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":20}}, "weight": 2},
                                        {"upstream": {"name": "upstream_B", "type": "roundrobin", "nodes": {"127.0.0.1:1982":10}}, "weight": 2},
                                        {"weight": 1}
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



=== TEST 12: expression validation failed, return to the default `route` upstream port `1980`
--- request
GET /server_port?name=jack&age=0
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 13: the expression passes and initiated multiple requests, the upstream traffic of `route` accounts for 1/5, and the upstream traffic of plugins accounts for 4/5
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=22', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 14: Multiple vars rules and multiple plugin upstream, do not split traffic to the upstream of `route`
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
                                        {"vars": [["arg_name", "==", "jack"], ["arg_age", "~~", "^[1-9]{1,2}"]]},
                                        {"vars": [["arg_name2", "in", ["jack", "rose"]], ["arg_age2", "!", "<", 18]]}
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":20}}, "weight": 2},
                                        {"upstream": {"name": "upstream_B", "type": "roundrobin", "nodes": {"127.0.0.1:1982":10}}, "weight": 2}
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



=== TEST 15: the expression passes and initiated multiple requests, do not split traffic to the upstream of `route`
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port?name=jack&age=22', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1981, 1981, 1981, 1982, 1982, 1982
--- no_error_log
[error]



=== TEST 16: support multiple ip configuration of `nodes`, and missing upstream configuration on `route`
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
                                            "vars": [["arg_name", "==", "jack"], ["arg_age", "~~", "^[1-9]{1,2}"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1980":1, "127.0.0.1:1981":2, "127.0.0.1:1982":2}, "timeout": {"connect": 15, "send": 15, "read": 15}}, "weight": 1}
                                    ]
                                }
                            ]
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



=== TEST 17: the expression passes and initiated multiple requests, roundrobin the ip of nodes
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=22', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981, 1981, 1982, 1982
--- no_error_log



=== TEST 18: host is domain name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                    "foo.com:80": 0
                                                }
                                            },
                                            "weight": 2
                                        },
                                        {
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
                }]]
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



=== TEST 19: domain name resolved successfully
--- request
GET /server_port
--- error_code: 502
--- error_log eval
qr/dns resolver domain: foo.com to \d+.\d+.\d+.\d+/



=== TEST 20: mock Grayscale Release
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                    "127.0.0.1:1981":1
                                                }
                                            },
                                            "weight": 2
                                        },
                                        {
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
                }]]
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



=== TEST 21: 2/3 request traffic hits the upstream of the plugin, 1/3 request traffic hits the upstream of `route`
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1981, 1981, 1981, 1981
--- no_error_log
[error]



=== TEST 22: mock Blue-green Release
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
                                            "vars": [["http_release","==","blue"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {
                                            "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
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



=== TEST 23: release is equal to `blue`
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["release"] = "blue"
        for i = 1, 6 do
            local _, _, body = t('/server_port', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1981, 1981, 1981, 1981, 1981, 1981
--- no_error_log
[error]



=== TEST 24: release is equal to `green`
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["release"] = "green"
        for i = 1, 6 do
            local _, _, body = t('/server_port', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1980, 1980, 1980, 1980
--- no_error_log
[error]



=== TEST 25: mock Custom Release
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
                                            "vars": [["arg_name", "==", "jack"], ["arg_age", ">", "23"],["http_appkey", "~~", "[a-z]{1,5}"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":20}}, "weight": 2},
                                        {"upstream": {"name": "upstream_B", "type": "roundrobin", "nodes": {"127.0.0.1:1982":10}}, "weight": 2},
                                        {"weight": 1}
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



=== TEST 26: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 27: `match` rule failed, `age` condition did not match
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["release"] = "green"
        for i = 1, 6 do
            local _, _, body = t('/server_port?name=jack&age=16', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1980, 1980, 1980, 1980
--- no_error_log
[error]



=== TEST 28: upstream nodes are array type and node is the domain name
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
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": [{"host":"foo.com", "port": 80, "weight": 0}]}, "weight": 2}
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



=== TEST 29: domain name resolved successfully
--- request
GET /server_port
--- error_code: 502
--- error_log eval
qr/dns resolver domain: foo.com to \d+.\d+.\d+.\d+/



=== TEST 30: the nodes of upstream are array type, with multiple nodes
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
                                            "vars": [["arg_name", "==", "jack"], ["arg_age", ">", "23"],["http_appkey", "~~", "[a-z]{1,5}"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1981, "weight": 2}, {"host":"127.0.0.1", "port":1982, "weight": 2}]}, "weight": 4},
                                        {"weight": 1}
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



=== TEST 31: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 32: the upstream node is an array type and has multiple upstream
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
                                            "vars": [["arg_name", "==", "jack"], ["arg_age", ">", "23"],["http_appkey", "~~", "[a-z]{1,5}"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1981, "weight": 2}]}, "weight": 2},
                                        {"upstream": {"name": "upstream_B", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1982, "weight": 2}]}, "weight": 2},
                                        {"weight": 1}
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



=== TEST 33: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981, 1981, 1982, 1982
--- no_error_log
[error]



=== TEST 34: multi-upstream, test with unique upstream key
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
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1981, "weight": 2}]}, "weight": 2},
                                        {"upstream": {"name": "upstream_B", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1982, "weight": 2}]}, "weight": 2}
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



=== TEST 35: the upstream `key` is unique
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 2 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1981, 1982
--- grep_error_log eval
qr/upstream_key: roundrobin#route_1_\d/
--- grep_error_log_out eval
qr/(upstream_key: roundrobin#route_1_1
upstream_key: roundrobin#route_1_2
|upstream_key: roundrobin#route_1_2
upstream_key: roundrobin#route_1_1
)/
--- no_error_log
[error]



=== TEST 36: has empty upstream, test the upstream key is unique
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
                                    "weighted_upstreams": [
                                        {"upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1981, "weight": 2}]}, "weight": 1},
                                        {"weight": 1}
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



=== TEST 37: the upstream `key` is unique
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 2 do
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1981
--- grep_error_log eval
qr/upstream_key: roundrobin#route_1_\d/
--- grep_error_log_out
upstream_key: roundrobin#route_1_1
--- no_error_log
[error]
