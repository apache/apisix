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
log_level('warn');
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

=== TEST 1: set route with serverless function to verify apisix_upstream_response_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": [
                                "return function(conf, ctx)
                                    local apisix_urt = ctx.var.apisix_upstream_response_time
                                    local ngx_urt = ngx.var.upstream_response_time
                                    if apisix_urt and ngx_urt and apisix_urt == ngx_urt then
                                        ngx.log(ngx.WARN, 'SUCCESS: apisix_upstream_response_time matches')
                                    else
                                        ngx.log(ngx.ERR, 'ERROR: apisix_upstream_response_time mismatch. APISIX: ', tostring(apisix_urt), ' NGX: ', tostring(ngx_urt))
                                    end
                                end"
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



=== TEST 2: verify apisix_upstream_response_time matches ngx.upstream_response_time
--- request
GET /hello
--- response_body
hello world
--- error_log
SUCCESS: apisix_upstream_response_time matches
--- no_error_log
ERROR: apisix_upstream_response_time mismatch
