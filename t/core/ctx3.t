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
log_level('debug');
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

=== TEST 1: parse graphql only once and use subsequent from cache
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
                                "functions" : ["return function(conf, ctx)
                                                ngx.log(ngx.WARN, 'find ctx._graphql: ', ctx.var.graphql_name == \"repo\");
                                                ngx.log(ngx.WARN, 'find ctx._graphql: ', ctx.var.graphql_name == \"repo\");
                                                ngx.log(ngx.WARN, 'find ctx._graphql: ', ctx.var.graphql_name == \"repo\");
                                                end"]
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



=== TEST 2: hit
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
--- grep_error_log eval
qr/serving ctx value from cache for key: graphql_name/
--- grep_error_log_out
serving ctx value from cache for key: graphql_name
serving ctx value from cache for key: graphql_name
serving ctx value from cache for key: graphql_name



=== TEST 3: parse post body only once when multiple different post_arg.* keys are accessed
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
                            "serverless-post-function": {
                                "phase": "rewrite",
                                "functions" : ["return function(conf, ctx)
                                                ngx.log(ngx.WARN, 'model: ', ctx.var['post_arg.model']);
                                                ngx.log(ngx.WARN, 'stream: ', ctx.var['post_arg.stream']);
                                                ngx.log(ngx.WARN, 'temperature: ', tostring(ctx.var['post_arg.temperature']));
                                                end"]
                            }
                        },
                        "uri": "/hello",
                        "vars": [
                            ["post_arg.model", "==", "gpt-4"]
                        ]
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



=== TEST 4: send request with multiple post_arg fields - body parsed only once
--- request
POST /hello
{"model":"gpt-4","stream":true,"temperature":0.7}
--- more_headers
Content-Type: application/json
--- response_body
hello world
--- error_code: 200
--- error_log
model: gpt-4
stream: true
temperature: 0.7
--- grep_error_log eval
qr/reuse parsed request body from ctx cache/
--- grep_error_log_out
reuse parsed request body from ctx cache
reuse parsed request body from ctx cache
