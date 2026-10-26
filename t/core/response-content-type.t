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
    my $lua = $block->response_lua // 'r.exit(200, {a = 1})';
    $block->set_value("config", qq{
        location = /t {
            default_type text/plain;
            charset off;
            content_by_lua_block {
                local r = require("apisix.core.response")
                $lua
            }
        }
    });
    $block->set_value("request", "GET /t") unless $block->request;
    $block->set_value("error_code", 200) unless defined $block->error_code;
    $block->set_value("no_error_log", "[error]") unless $block->no_error_log || $block->error_log;
});

run_tests;

__DATA__

=== TEST 1: single table
--- response_body eval
"{\"a\":1}\n"
--- response_headers
Content-Type: application/json



=== TEST 2: Accept does not change the existing JSON body
--- more_headers
Accept: application/xml, */*
--- response_body eval
"{\"a\":1}\n"
--- response_headers
Content-Type: application/json
!Vary



=== TEST 3: mixed table and string
--- response_lua
r.exit(200, {a = 1}, "tail")
--- response_body eval
"{\"a\":1}\ntail"
--- response_headers
Content-Type: text/plain



=== TEST 4: encoded JSON string
--- response_lua
r.exit(200, [[{"a":1}]])
--- response_body eval
"{\"a\":1}"
--- response_headers
Content-Type: text/plain



=== TEST 5: explicit nonempty type
--- response_lua
r.set_header("Content-Type", "application/problem+json")
r.exit(200, {a = 1})
--- response_body eval
"{\"a\":1}\n"
--- response_headers
Content-Type: application/problem+json



=== TEST 6: say remains incremental
--- response_lua
r.say({a = 1})
ngx.print("tail")
--- response_body eval
"{\"a\":1}\ntail"
--- response_headers
Content-Type: text/plain



=== TEST 7: already sent headers
--- response_lua
ngx.print("prefix")
r.exit(200, {a = 1})
--- response_body eval
"prefix{\"a\":1}\n"
--- response_headers
Content-Type: text/plain
--- error_log
attempt to set ngx.status after sending out response headers



=== TEST 8: callback string to table
--- response_lua
r.exit_insert_callback(function(code, body, headers)
    return code, {a = 1}, headers
end, {})
r.exit(200, "before")
--- response_body eval
"{\"a\":1}\n"
--- response_headers
Content-Type: application/json



=== TEST 9: callback table to string
--- response_lua
r.exit_insert_callback(function(code, body, headers)
    return code, "after", headers
end, {})
r.exit(200, {a = 1})
--- response_body eval
"after"
--- response_headers
Content-Type: text/plain



=== TEST 10: callback explicit type
--- response_lua
r.exit_insert_callback(function(code, body, headers)
    headers["Content-Type"] = "text/custom"
    return code, body, headers
end, {})
r.exit(200, {a = 1})
--- response_body eval
"{\"a\":1}\n"
--- response_headers
Content-Type: text/custom



=== TEST 11: encoding failure does not set JSON type
--- response_lua
local ok = pcall(r.exit, 200, {invalid = function() end})
ngx.print(tostring(ok))
--- response_body eval
"false"
--- response_headers
Content-Type: text/plain



=== TEST 12: HEAD status 200
--- request
HEAD /t
--- response_body
--- response_headers
Content-Type: application/json



=== TEST 13: GET status 204
--- response_lua
r.exit(204, {a = 1})
--- error_code: 204
--- response_body
--- response_headers
Content-Type:



=== TEST 14: GET status 304
--- response_lua
r.exit(304, {a = 1})
--- error_code: 304
--- response_body
--- response_headers
Content-Type:
