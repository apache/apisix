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
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 0
_EOC_
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: default behavior (min_interval=0) - router rebuilds on every route change
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 2: hit route to trigger router rebuild
--- request
GET /hello
--- response_body
hello world
--- no_error_log
skip router rebuild



=== TEST 3: update route to trigger another rebuild
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1981": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 4: hit route - should rebuild immediately (min_interval=0)
--- request
GET /hello
--- response_body_like eval
qr/hello world/
--- no_error_log
skip router rebuild



=== TEST 5: set router_rebuild_min_interval to 2 seconds and create initial route
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 6: hit route to trigger initial router build
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 2
--- request
GET /hello
--- response_body
hello world
--- no_error_log
skip router rebuild



=== TEST 7: update route and request immediately - rebuild should be skipped
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1981": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- request immediately after route change, within min_interval
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                ngx.say("request failed: ", err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        }
    }
--- request
GET /t
--- response_body
status: 200
body: hello world
--- error_log
skip router rebuild



=== TEST 8: wait for min_interval to pass, then rebuild should happen
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- update route
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- wait for min_interval to expire
            ngx.sleep(2.1)

            -- this request should trigger a rebuild
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                ngx.say("request failed: ", err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        }
    }
--- request
GET /t
--- response_body
status: 200
body: hello world
--- no_error_log
skip router rebuild
--- timeout: 5



=== TEST 9: rapid route updates within min_interval - only one rebuild
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
        router_rebuild_min_interval: 3
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            -- create initial route and trigger first build
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- trigger initial build
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                ngx.say("initial request failed: ", err)
                return
            end

            -- rapid updates (simulating high-frequency route changes)
            for i = 1, 5 do
                t('/apisix/admin/routes/1',
                     ngx.HTTP_PUT,
                     [[{
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                    }]]
                    )
                -- request after each update
                httpc = http.new()
                res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
                if not res then
                    ngx.say("request ", i, " failed: ", err)
                    return
                end
            end

            ngx.say("all requests succeeded")
        }
    }
--- request
GET /t
--- response_body
all requests succeeded
--- error_log
skip router rebuild
