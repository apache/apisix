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

run_tests;

__DATA__

=== TEST 1: origin request log skips body when include_req_body_expr is false
--- config
    location /t {
        content_by_lua_block {
            ngx.req.read_body()

            local log_util = require("apisix.utils.log-util")
            local ctx = {
                var = {
                    request = ngx.var.request,
                    arg_log_body = ngx.var.arg_log_body,
                }
            }
            local conf = {
                include_req_body = true,
                include_req_body_expr = {
                    {"arg_log_body", "==", "yes"}
                }
            }

            local entry = log_util.get_req_original(ctx, conf)
            if entry:find("hidden request body", 1, true) then
                ngx.say("body logged")
                return
            end

            ngx.say("body skipped")
        }
    }
--- request
POST /t?log_body=no
hidden request body
--- response_body
body skipped



=== TEST 2: origin request log keeps body when include_req_body_expr is true
--- config
    location /t {
        content_by_lua_block {
            ngx.req.read_body()

            local log_util = require("apisix.utils.log-util")
            local ctx = {
                var = {
                    request = ngx.var.request,
                    arg_log_body = ngx.var.arg_log_body,
                }
            }
            local conf = {
                include_req_body = true,
                include_req_body_expr = {
                    {"arg_log_body", "==", "yes"}
                }
            }

            local entry = log_util.get_req_original(ctx, conf)
            if entry:find("visible request body", 1, true) then
                ngx.say("body logged")
                return
            end

            ngx.say("body skipped")
        }
    }
--- request
POST /t?log_body=yes
visible request body
--- response_body
body logged
