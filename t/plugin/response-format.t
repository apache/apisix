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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("extra_yaml_config", "plugins:\n  - key-auth\n  - response-rewrite\n");
});

run_tests;

__DATA__

=== TEST 1: configure response negotiation routes
--- config
    location = /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, explicit in ipairs({false, true}) do
                local rewrite = {body = "replacement"}
                if explicit then
                    rewrite.headers = {set = {["Content-Type"] = "text/plain"}}
                end
                local route = {
                    uri = explicit and "/pr8511/rewrite-set" or "/pr8511/rewrite-body",
                    plugins = {["key-auth"] = {}, ["response-rewrite"] = rewrite},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
                }
                local code, body = t("/apisix/admin/routes/" ..
                    (explicit and "rewrite-set" or "rewrite-body"), ngx.HTTP_PUT,
                    require("cjson").encode(route))
                assert(code < 300, body)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: body-only rewrite retains negotiated type
--- request
GET /pr8511/rewrite-body
--- more_headers
Accept: application/json
--- error_code: 401
--- response_headers
Content-Type: application/json
--- response_body eval
"replacement"
--- no_error_log
[error]



=== TEST 3: explicit rewrite type
--- request
GET /pr8511/rewrite-set
--- more_headers
Accept: application/json
--- error_code: 401
--- response_headers
Content-Type: text/plain
--- response_body eval
"replacement"
--- no_error_log
[error]
