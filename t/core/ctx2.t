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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->response_body) {
        $block->set_value("response_body", "passed\n");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: should update cached ctx.var
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "functions" : ["return function(conf, ctx)
                                        ngx.log(ngx.WARN, 'pre uri: ', ctx.var.upstream_uri);
                                        ctx.var.upstream_uri = '/server_port';
                                        ngx.log(ngx.WARN, 'post uri: ', ctx.var.upstream_uri);
                                        end"]
                        },
                        "proxy-rewrite": {
                            "uri": "/hello"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/xxx"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 2: check
--- request
GET /xxx
--- response_body chomp
1980
--- error_log
pre uri: /hello
post uri: /server_port



=== TEST 3: get balancer_ip and balancer_port through ctx.var
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "log",
                            "functions" : ["return function(conf, ctx)
                                        ngx.log(ngx.WARN, 'balancer_ip: ', ctx.var.balancer_ip)
                                        ngx.log(ngx.WARN, 'balancer_port: ', ctx.var.balancer_port)
                                        end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 4: check(balancer_ip is 127.0.0.1 and balancer_port is 1980)
--- request
GET /hello
--- response_body
hello world
--- grep_error_log eval
qr/balancer_ip: 127.0.0.1|balancer_port: 1980/
--- grep_error_log_out
balancer_ip: 127.0.0.1
balancer_port: 1980



=== TEST 5: parsed graphql is cached under ctx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["POST"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "header_filter",
                                "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, 'find ctx._graphql: ', ctx._graphql ~= nil) end"]
                            }
                        },
                        "uri": "/hello",
                        "vars": [["graphql_name", "==", "repo"]]
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



=== TEST 6: hit
--- request
POST /hello
query repo {
    owner {
        name
    }
}
--- response_body
hello world
--- error_log
find ctx._graphql: true



=== TEST 7: support dash in the args
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["arg_a-b", "==", "ab"]]
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 8: check (support dash in the args)
--- request
GET /hello?a-b=ab
--- response_body
hello world



=== TEST 9: support dash in the args(Multi args with the same name, only fetch the first one)
--- request
GET /hello?a-b=ab&a-b=ccc
--- response_body
hello world



=== TEST 10: support dash in the args(arg is missing)
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 11: parsed post args is cached under ctx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, 'find ctx.req_post_args.test: ', ctx.req_post_args.test ~= nil) end"]
                            }
                        },
                        "uri": "/hello",
                        "vars": [["post_arg_test", "==", "test"]]
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



=== TEST 12: hit
--- request
POST /hello
test=test
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- response_body
hello world
--- error_log
find ctx.req_post_args.test: true



=== TEST 13: missed (post_arg_test is missing)
--- request
POST /hello
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 14: missed (post_arg_test is mismatch)
--- request
POST /hello
test=tesy
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 15: register custom variable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions" : ["return function(conf, ctx) ngx.say('find ctx.var.a6_labels_zone: ', ctx.var.a6_labels_zone) end"]
                            }
                        },
                        "uri": "/hello",
                        "labels": {
                            "zone": "Singapore"
                        }
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 16: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local core = require "apisix.core"
            core.ctx.register_var("a6_labels_zone", function(ctx)
                local route = ctx.matched_route and ctx.matched_route.value
                if route and route.labels then
                    return route.labels.zone
                end
                return nil
            end)
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res = assert(httpc:request_uri(uri))
            ngx.print(res.body)
        }
    }
--- response_body
find ctx.var.a6_labels_zone: Singapore



=== TEST 17: register custom variable with no cacheable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions" : ["return function(conf, ctx) ngx.say('find ctx.var.a6_count: ', ctx.var.a6_count) end"]
                            },
                            "serverless-post-function": {
                                "phase": "rewrite",
                                "functions" : ["return function(conf, ctx) ngx.say('find ctx.var.a6_count: ', ctx.var.a6_count) end"]
                            }
                        },
                        "uri": "/hello"
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 18: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local core = require "apisix.core"
            core.ctx.register_var("a6_count", function(ctx)
                if not ctx.a6_count then
                    ctx.a6_count = 0
                end
                ctx.a6_count = ctx.a6_count + 1
                return ctx.a6_count
            end, {no_cacheable = true})
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res = assert(httpc:request_uri(uri))
            ngx.print(res.body)
        }
    }
--- response_body
find ctx.var.a6_count: 1
find ctx.var.a6_count: 2
