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

=== TEST 1: mock Blue-green Release
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
                      vars = { { "http_release", "==", "blue" } }
                    } },
                    weighted_upstreams = { {
                      upstream = {
                        name = "upstream_A",
                        type = "roundrobin",
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
                ngx.HTTP_PUT,
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



=== TEST 2: release is equal to `blue`
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
--- response_body
1981, 1981, 1981, 1981, 1981, 1981



=== TEST 3: release is equal to `green`
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
--- response_body
1980, 1980, 1980, 1980, 1980, 1980



=== TEST 4: mock Custom Release
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
--- response_body
passed



=== TEST 5: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["appkey"] = "api-key"
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1981, 1981, 1982, 1982



=== TEST 6: `match` rule failed, `age` condition did not match
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
--- response_body
1980, 1980, 1980, 1980, 1980, 1980



=== TEST 7: upstream nodes are array type and node is the domain name
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
--- response_body
passed



=== TEST 8: domain name resolved successfully
--- request
GET /server_port
--- error_code: 502
--- error_log eval
qr/dns resolver domain: foo.com to \d+.\d+.\d+.\d+/



=== TEST 9: the nodes of upstream are array type, with multiple nodes
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
--- response_body
passed



=== TEST 10: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["appkey"] = "api-key"
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1981, 1981, 1982, 1982



=== TEST 11: the upstream node is an array type and has multiple upstream
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
--- response_body
passed



=== TEST 12: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["appkey"] = "api-key"
        for i = 1, 5 do
            local _, _, body = t('/server_port?name=jack&age=36', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1981, 1981, 1982, 1982



=== TEST 13: multi-upstream, test with unique upstream key
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
--- response_body
passed



=== TEST 14: the upstream `key` is unique
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



=== TEST 15: has empty upstream, test the upstream key is unique
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
--- response_body
passed



=== TEST 16: the upstream `key` is unique
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
--- response_body
1980, 1981
--- grep_error_log eval
qr/upstream_key: roundrobin#route_1_\d/
--- grep_error_log_out
upstream_key: roundrobin#route_1_1



=== TEST 17: schema validation, "additionalProperties = false" to limit the plugin configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.traffic-split")
            local ok, err = plugin.check_schema({
                additional_properties = "hello",
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
--- response_body eval
qr/additional properties forbidden, found additional_properties/



=== TEST 18: schema validation, "additionalProperties = false" to limit the "rules" configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.traffic-split")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        additional_properties = "hello",
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
--- response_body eval
qr/property "rules" validation failed: failed to validate item 1: additional properties forbidden, found additional_properties/



=== TEST 19: the request header contains horizontal lines("-")
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
                                            "vars": [["http_x-api-appkey", "==", "api-key"]]
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
--- response_body
passed



=== TEST 20: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["x-api-appkey"] = "api-key"
        for i = 1, 5 do
            local _, _, body = t('/server_port', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1981, 1981, 1982, 1982



=== TEST 21: request args and request headers contain horizontal lines("-")
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
                                            "vars": [["arg_x-api-name", "==", "jack"], ["arg_x-api-age", ">", "23"],["http_x-api-appkey", "~~", "[a-z]{1,5}"]]
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
--- response_body
passed



=== TEST 22: `match` rule passed
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["x-api-appkey"] = "hello"
        for i = 1, 5 do
            local _, _, body = t('/server_port?x-api-name=jack&x-api-age=36', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.print(table.concat(bodys, ", "))
    }
}
--- response_body chomp
1980, 1981, 1981, 1982, 1982
