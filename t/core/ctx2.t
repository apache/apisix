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
