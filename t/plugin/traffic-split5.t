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

    my $http_config = $block->http_config // <<_EOC_;
    # fake server, only for test
    server {
        listen 1970;
        location / {
            content_by_lua_block {
                ngx.say(1970)
            }
        }
    }

    server {
        listen 1971;
        location / {
            content_by_lua_block {
                ngx.say(1971)
            }
        }
    }

    server {
        listen 1972;
        location / {
            content_by_lua_block {
                ngx.say(1972)
            }
        }
    }

    server {
        listen 1973;
        location / {
            content_by_lua_block {
                ngx.say(1973)
            }
        }
    }

    server {
        listen 1974;
        location / {
            content_by_lua_block {
                ngx.say(1974)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set upstream(multiple rules, multiple nodes under each weighted_upstreams) and add route
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/hello",
                plugins = {
                    ["traffic-split"] = {
                        rules = {
                            {
                                match = { {
                                    vars = { { "arg_id", "==", "1" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_A",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1970"] = 1,
                                                ["127.0.0.1:1971"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            },
                            {
                                match = { {
                                    vars = { { "arg_id", "==", "2" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_B",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1972"] = 1,
                                                ["127.0.0.1:1973"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            }
                        }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1974"] = 1
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



=== TEST 2: hit different weighted_upstreams by rules
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri)
            local port = tonumber(res.body)
            if port ~= 1974 then
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("failed while no arg_id")
                return
            end

            uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=1"
            res, err = httpc:request_uri(uri)
            port = tonumber(res.body)
            if port ~= 1970 and port ~= 1971 then
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("failed while arg_id = 1")
                return
            end

            uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=2"
            res, err = httpc:request_uri(uri)
            port = tonumber(res.body)
            if port ~= 1972 and port ~= 1973 then
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("failed while arg_id = 2")
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: set upstream(multiple rules, multiple nodes with different weight under each weighted_upstreams) and add route
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/hello",
                plugins = {
                    ["traffic-split"] = {
                        rules = {
                            {
                                match = { {
                                    vars = { { "arg_id", "==", "1" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_A",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1970"] = 2,
                                                ["127.0.0.1:1971"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            },
                            {
                                match = { {
                                    vars = { { "arg_id", "==", "2" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_B",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1972"] = 2,
                                                ["127.0.0.1:1973"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            }
                        }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1974"] = 1
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



=== TEST 4: pick different nodes by weight
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=1"
            local ports = {}
            local res, err
            for i = 1, 3 do
                res, err = httpc:request_uri(uri)
                local port = tonumber(res.body)
                ports[i] = port
            end
            table.sort(ports)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=2"
            for i = 4, 6 do
                res, err = httpc:request_uri(uri)
                local port = tonumber(res.body)
                ports[i] = port
            end
            table.sort(ports)

            ngx.say(table.concat(ports, ", "))
        }
    }
--- response_body
1970, 1970, 1971, 1972, 1972, 1973



=== TEST 5: set upstream(multiple rules, the first rule has the match attribute and the second rule does not) and add route
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/hello",
                plugins = {
                    ["traffic-split"] = {
                        rules = {
                            {
                                match = { {
                                    vars = { { "arg_id", "==", "1" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_A",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1970"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            },
                            {
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_B",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1971"] = 1
                                            }
                                        },
                                        weight = 1
                                    },
                                    {
                                        weight = 1
                                    }
                               }
                            }
                        }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1972"] = 1
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



=== TEST 6: first rule match failed and the second rule match success
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=1"
            local ports = {}
            local res, err
            for i = 1, 2 do
                res, err = httpc:request_uri(uri)
                local port = tonumber(res.body)
                ports[i] = port
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?id=2"
            for i = 3, 4 do
                res, err = httpc:request_uri(uri)
                local port = tonumber(res.body)
                ports[i] = port
            end
            table.sort(ports)

            ngx.say(table.concat(ports, ", "))
        }
    }
--- response_body
1970, 1970, 1971, 1972



=== TEST 7: set up traffic-split rule
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
                                vars = { { "arg_name", "==", "jack" } }
                            } },
                            weighted_upstreams = { {
                                upstream = {
                                    type = "roundrobin",
                                    nodes = {
                                        ["127.0.0.1:1979"] = 1
                                    },
                                },
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



=== TEST 8: hit and check default timeout
--- http_config
proxy_connect_timeout 12345s;
--- request
GET /server_port?name=jack
--- log_level: debug
--- error_log eval
qr/event timer add: \d+: 12345000:\d+/
--- error_code: 502



=== TEST 9: set upstream for post_arg_id test case
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/hello",
                plugins = {
                    ["traffic-split"] = {
                        rules = {
                            {
                                match = { {
                                    vars = { { "post_arg_id", "==", "1" } }
                                } },
                                weighted_upstreams = {
                                    {
                                        upstream = {
                                            name = "upstream_A",
                                            type = "roundrobin",
                                            nodes = {
                                                ["127.0.0.1:1970"] = 1
                                            }
                                        },
                                        weight = 1
                                    }
                               }
                            }
                        }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1974"] = 1
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



=== TEST 10: post_arg_id = 1 without content-type charset
--- request
POST /hello
id=1
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- response_body
1970



=== TEST 11: post_arg_id = 1 with content-type charset
--- request
POST /hello
id=1
--- more_headers
Content-Type: application/x-www-form-urlencoded;charset=UTF-8
--- response_body
1970



=== TEST 6: failure after plugin reload
--- extra_yaml_config
nginx_config:
  worker_processes: 1

--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{                 
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1970":10
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/upstreams/2',
                 ngx.HTTP_PUT,
                 [[{                 
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1971":10
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
                 [[{
                    "uri": "/hello",
                    "plugins": {
                        "traffic-split": {
                            "rules": [
                                {
                                    "weighted_upstreams": [
                                        {
                                            "upstream_id": "2",
                                            "weight": 1
                                        },
                                        {
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream_id": "1"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t('/hello')
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/hello')
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed.")
        }
    }
--- request
GET /t
--- response_body
passed.
