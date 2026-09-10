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
# run_global_rules() caches the filtered plugin list on api_ctx instead of
# re-filtering in every phase, and _M.filter() takes a fast path that iterates
# the enabled set rather than every loaded plugin. Neither may change *which*
# plugins run, in what order, or when the cached set has to be rebuilt.
use t::APISIX 'no_plan';

no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: global rule running a plugin in more than one phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function() ngx.log(ngx.WARN, 'gr-phase: rewrite') end"
                            ]
                        },
                        "serverless-post-function": {
                            "phase": "body_filter",
                            "functions": [
                                "return function() ngx.log(ngx.WARN, 'gr-phase: body_filter') end"
                            ]
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



=== TEST 2: set route
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
--- response_body
passed



=== TEST 3: every phase still runs off the cached plugin list
--- request
GET /hello
--- response_body
hello world
--- error_log
gr-phase: rewrite
gr-phase: body_filter



=== TEST 4: body_filter still runs for every chunk of a chunked response
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello_chunked"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            local res = httpc:request_uri("http://127.0.0.1:" ..
                                          ngx.var.server_port .. "/hello_chunked")
            ngx.say(res.status)
        }
    }
--- response_body
200
--- grep_error_log eval
qr/gr-phase: body_filter/
--- grep_error_log_out eval
qr/(gr-phase: body_filter\n){2,}/



=== TEST 5: the cache is rebuilt when the global rule changes mid-flight
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            httpc:request_uri(base .. "/hello")

            -- new modifiedIndex => the cached set must not be reused
            local code = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function() ngx.log(ngx.WARN, 'gr-phase: reloaded') end"
                            ]
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.5)
            local res = httpc:request_uri(base .. "/hello")
            ngx.say(res.status)
        }
    }
--- response_body
200
--- error_log
gr-phase: reloaded



=== TEST 6: clean up the global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
