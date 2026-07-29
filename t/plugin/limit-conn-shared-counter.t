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

log_level('info');
repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    my $port = $ENV{TEST_NGINX_SERVER_PORT};

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # limit-conn counts *concurrent* connections and releases the counter in the
    # log phase, so the requests have to overlap: pipelined requests are handled
    # one after another and would never hit the limit.
    my $config = $block->config // <<_EOC_;
    location /concurrent {
        content_by_lua_block {
            local httpc = require("resty.http")

            local function hit(uri, apikey)
                local hc = httpc:new()
                local res, err = hc:request_uri("http://127.0.0.1:$port" .. uri,
                                                {headers = {apikey = apikey}})
                if not res then
                    ngx.log(ngx.ERR, "request to ", uri, " failed: ", err)
                    return 0
                end
                return res.status
            end

            -- two_routes: same consumer hits two different routes
            -- two_consumers: two consumers hit the same route
            local reqs = {
                two_routes = {{"/limit_conn", "jack-key"}, {"/limit_conn2", "jack-key"}},
                two_consumers = {{"/limit_conn", "jack-key"}, {"/limit_conn", "bob-key"}},
            }

            local threads = {}
            for i, req in ipairs(reqs[ngx.var.arg_case]) do
                threads[i] = ngx.thread.spawn(hit, req[1], req[2])
            end

            local codes = {}
            for i, th in ipairs(threads) do
                local _, status = ngx.thread.wait(th)
                codes[i] = status
            end

            table.sort(codes)
            ngx.say(table.concat(codes, ","))
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: consumer jack with limit-conn (conn = 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "jack-key"
                        },
                        "limit-conn": {
                            "conn": 1,
                            "burst": 0,
                            "default_conn_delay": 0.1,
                            "rejected_code": 503,
                            "key": "consumer_name"
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
--- response_body
passed



=== TEST 2: consumer bob with its own limit-conn (conn = 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/bob',
                ngx.HTTP_PUT,
                [[{
                    "username": "bob",
                    "plugins": {
                        "key-auth": {
                            "key": "bob-key"
                        },
                        "limit-conn": {
                            "conn": 1,
                            "burst": 0,
                            "default_conn_delay": 0.1,
                            "rejected_code": 503,
                            "key": "consumer_name"
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
--- response_body
passed



=== TEST 3: set 2 routes with key-auth, both proxying to the slow upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/limit_conn",
                    "plugins": {
                        "key-auth": {}
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
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/limit_conn2",
                    "plugins": {
                        "key-auth": {},
                        "proxy-rewrite": {
                            "uri": "/limit_conn"
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
--- response_body
passed



=== TEST 4: the counter is shared across routes and keyed by the consumer
--- request
GET /concurrent?case=two_routes
--- response_body
200,503
--- error_log eval
qr/limit key: \/apisix\/consumers\/jack:\d+:jack/
--- timeout: 10



=== TEST 5: different consumers keep their own counter
--- request
GET /concurrent?case=two_consumers
--- response_body
200,200
--- timeout: 10
