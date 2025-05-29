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

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("no_error_log", "[error]");
    $block;
});

no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: Sanity check - plugin schema validation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ok, err = plugin.check_schema({
                services = {
                    { uri = "http://127.0.0.1:${TEST_NGINX_SERVER_PORT}/test", method = "POST" }
                },
                token_header = "Token"
            })
            if not ok then
                ngx.say("failed to check schema: ", err)
            else
                ngx.say("schema check passed")
            end
        }
    }
--- request
GET /t
--- response_body
schema check passed
--- no_error_log
[error]

=== TEST 2: Successful chaining - single service with token
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'
            ctx.var.Token = "my-auth-token"

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:${TEST_NGINX_SERVER_PORT}/test", method = "POST" }
                },
                token_header = "Token"
            }

            local code, body = plugin.access(conf, ctx)
            if code then
                ngx.status = code
                ngx.say(body.error)
            else
                ngx.say(ctx.var.request_body)
            end
        }
    }
    location /test {
        content_by_lua_block {
            ngx.say('{"user_id": "67890"}')
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
{"order_id":"12345","user_id":"67890"}
--- no_error_log
[error]

=== TEST 3: Multiple services chaining
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'
            ctx.var.Token = "my-auth-token"

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:${TEST_NGINX_SERVER_PORT}/test1", method = "POST" },
                    { uri = "http://127.0.0.1:${TEST_NGINX_SERVER_PORT}/test2", method = "POST" }
                },
                token_header = "Token"
            }

            local code, body = plugin.access(conf, ctx)
            if code then
                ngx.status = code
                ngx.say(body.error)
            else
                ngx.say(ctx.var.request_body)
            end
        }
    }
    location /test1 {
        content_by_lua_block {
            ngx.say('{"user_id": "67890"}')
        }
    }
    location /test2 {
        content_by_lua_block {
            ngx.say('{"status": "valid"}')
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
{"order_id":"12345","user_id":"67890","status":"valid"}
--- no_error_log
[error]

=== TEST 4: Error handling - service failure
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:1999/nonexistent", method = "POST" }
                }
            }

            local code, body = plugin.access(conf, ctx)
            ngx.status = code
            ngx.say(body.error)
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
Failed to call service: http://127.0.0.1:1999/nonexistent
--- error_code: 500
--- error_log
Failed to call service http://127.0.0.1:1999/nonexistent

=== TEST 5: Handle missing token
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:${TEST_NGINX_SERVER_PORT}/test", method = "POST" }
                },
                token_header = "Token"
            }

            local code, body = plugin.access(conf, ctx)
            if code then
                ngx.status = code
                ngx.say(body.error)
            else
                ngx.say(ctx.var.request_body)
            end
        }
    }
    location /test {
        content_by_lua_block {
            ngx.say('{"user_id": "67890"}')
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
{"order_id":"12345","user_id":"67890"}
--- no_error_log
[error]
