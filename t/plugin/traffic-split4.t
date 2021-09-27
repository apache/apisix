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

    if (!$block->error_log && !$block->no_error_log &&
        (defined $block->error_code && $block->error_code != 502))
    {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: set upstream(id: 1)
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
                    "desc": "new upstream"
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



=== TEST 2: set upstream(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                 ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1982": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
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



=== TEST 3: set route(id: 1, upstream_id: 1, upstream_id in plugin: 2), and `weighted_upstreams` does not have a structure with only `weight`
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
                                            "vars": [["arg_name", "==", "James"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 2}
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream_id":"1"
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



=== TEST 4: when `match` rule passed, use the `upstream_id` in plugin, and when it failed, use the `upstream_id` in route
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}

        for i = 1, 5, 2 do
            -- match rule passed
            local _, _, body = t('/server_port?name=James', ngx.HTTP_GET)
            bodys[i] = body

             -- match rule failed
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i+1] = body
        end

        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1981, 1981, 1981, 1982, 1982, 1982



=== TEST 5: set route(use upstream for route and upstream_id for plugin), and `weighted_upstreams` does not have a structure with only `weight`
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
                                            "vars": [["arg_name", "==", "James"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 1}
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



=== TEST 6: when `match` rule passed, use the `upstream_id` in plugin, and when it failed, use the `upstream` in route
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}

        for i = 1, 5, 2 do
            -- match rule passed
            local _, _, body = t('/server_port?name=James', ngx.HTTP_GET)
            bodys[i] = body

             -- match rule failed
            local _, _, body = t('/server_port', ngx.HTTP_GET)
            bodys[i+1] = body
        end

        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1980, 1980, 1981, 1981, 1981



=== TEST 7: set route(id: 1, upstream_id: 1, upstream_id in plugin: 2), and `weighted_upstreams` has a structure with only `weight`
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
                                            "vars": [["uri", "==", "/server_port"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 2, "weight": 1},
                                        {"weight": 1}
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream_id":"1"
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



=== TEST 8: all requests `match` rule passed, proxy requests to the upstream of route based on the structure with only `weight` in `weighted_upstreams`
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
--- response_body
1981, 1981, 1981, 1982, 1982, 1982



=== TEST 9: the upstream_id is used in the plugin
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
                                            "vars": [["arg_x-api-name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 1, "weight": 2},
                                        {"upstream_id": 2, "weight": 1},
                                        {"weight": 2}
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



=== TEST 10: `match` rule passed(upstream_id)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        for i = 1, 5 do
            local _, _, body = t('/server_port?x-api-name=jack', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1980, 1981, 1981, 1982



=== TEST 11: only use upstream_id in the plugin
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
                                            "vars": [["arg_x-api-name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 1, "weight": 1},
                                        {"upstream_id": 2, "weight": 1}
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



=== TEST 12: `match` rule passed(only use upstream_id)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 4 do
            local _, _, body = t('/server_port?x-api-name=jack', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1981, 1981, 1982, 1982



=== TEST 13: use upstream and upstream_id in the plugin
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
                                            "vars": [["arg_x-api-name", "==", "jack"]]
                                        }
                                    ],
                                    "weighted_upstreams": [
                                        {"upstream_id": 1, "weight": 2},
                                        {"upstream": {"type": "roundrobin", "nodes": [{"host":"127.0.0.1", "port":1982, "weight": 1}]}, "weight": 1},
                                        {"weight": 2}
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



=== TEST 14: `match` rule passed(upstream + upstream_id)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local headers = {}
        headers["x-api-appkey"] = "hello"
        for i = 1, 5 do
            local _, _, body = t('/server_port?x-api-name=jack', ngx.HTTP_GET, "", nil, headers)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- response_body
1980, 1980, 1981, 1981, 1982



=== TEST 15: set route + upstream (two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1981": 1,
                        "127.0.0.1:1970": 1
                    },
                    "checks": {
                        "active": {
                            "http_path": "/status",
                            "host": "foo.com",
                            "healthy": {
                                "interval": 1,
                                "successes": 1
                            },
                            "unhealthy": {
                                "interval": 1,
                                "http_failures": 2
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/server_port",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {"upstream_id": 1, "weight": 1}
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



=== TEST 16: hit routes, ensure the checker is bound to the upstream
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local uri = "http://127.0.0.1:" .. ngx.var.server_port
                    .. "/server_port"

        do
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
        end

        ngx.sleep(2.5)

        local ports_count = {}
        for i = 1, 6 do
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            if not res then
                ngx.say(err)
                return
            end

            ports_count[res.body] = (ports_count[res.body] or 0) + 1
        end

        local ports_arr = {}
        for port, count in pairs(ports_count) do
            table.insert(ports_arr, {port = port, count = count})
        end

        local function cmd(a, b)
            return a.port > b.port
        end
        table.sort(ports_arr, cmd)

        ngx.say(require("toolkit.json").encode(ports_arr))
        ngx.exit(200)
    }
}
--- response_body
[{"count":6,"port":"1981"}]
--- grep_error_log eval
qr/\([^)]+\) unhealthy .* for '.*'/
--- grep_error_log_out
(upstream#/apisix/upstreams/1) unhealthy TCP increment (1/2) for 'foo.com(127.0.0.1:1970)'
(upstream#/apisix/upstreams/1) unhealthy TCP increment (2/2) for 'foo.com(127.0.0.1:1970)'
--- timeout: 10



=== TEST 17: set upstream(id: 1), by default retries count = number of nodes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1": 1,
                        "127.0.0.2:1": 1,
                        "127.0.0.3:1": 1
                    },
                    "type": "roundrobin"
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



=== TEST 18: set route(id: 1, upstream_id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {"upstream_id": 1, "weight": 1}
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



=== TEST 19: hit routes
--- request
GET /hello
--- error_code: 502
--- grep_error_log eval
qr/\([^)]+\) while connecting to upstream/
--- grep_error_log_out
(111: Connection refused) while connecting to upstream
(111: Connection refused) while connecting to upstream
(111: Connection refused) while connecting to upstream
