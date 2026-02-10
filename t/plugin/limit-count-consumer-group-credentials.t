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
    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup consumer group with limit-count plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/test_group',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "policy": "local"
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



=== TEST 2: setup consumer with group_id (no direct plugins)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "group_id": "test_group"
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



=== TEST 3: setup credentials via credentials endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/cred-jack',
                ngx.HTTP_PUT,
                [[{
                    "id": "cred-jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
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



=== TEST 4: setup route with key-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
                    },
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



=== TEST 5: verify rate limiting works (all 3 requests in one test)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Request 1: should succeed
            local res1, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-jack"
                    }
                }
            )

            if not res1 or res1.status ~= 200 then
                ngx.say("request 1 failed: ", res1 and res1.status or err)
                return
            end

            -- Request 2: should succeed
            local res2, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-jack"
                    }
                }
            )

            if not res2 or res2.status ~= 200 then
                ngx.say("request 2 failed: ", res2 and res2.status or err)
                return
            end

            -- Request 3: should be rate limited
            local res3, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-jack"
                    }
                }
            )

            if res3.status == 429 then
                ngx.say("rate limiting works correctly")
            else
                ngx.say("expected 429, got: ", res3.status)
            end
        }
    }
--- response_body
rate limiting works correctly



=== TEST 6: setup second consumer group with higher limit
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/premium_group',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 10,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "policy": "local"
                        }
                    }
                }]]
            )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: setup premium consumer with credentials
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers/jane',
                ngx.HTTP_PUT,
                [[{
                    "username": "jane",
                    "group_id": "premium_group"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/consumers/jane/credentials/cred-jane',
                ngx.HTTP_PUT,
                [[{
                    "id": "cred-jane",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jane"
                        }
                    }
                }]]
            )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: verify premium consumer has higher limit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Make 10 requests (all should succeed)
            for i = 1, 10 do
                local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                    "/hello", {
                        method = "GET",
                        headers = {
                            ["apikey"] = "auth-jane"
                        }
                    })

                    if not res then
                        ngx.say("request ", i, " failed: ", err)
                        return
                    end

                    if res.status ~= 200 then
                        ngx.say("request ", i, " unexpected status: ", res.status)
                        return
                    end
            end


            -- should be rate limited
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-jane"
                    }
                }
            )

            if res.status == 429 then
                ngx.say("rate limiting works correctly")
            else
                ngx.say("expected 429, got: ", res.status)
            end
        }
    }
--- response_body
rate limiting works correctly



=== TEST 9: setup consumer with both direct plugins and group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers/mixed_user',
                ngx.HTTP_PUT,
                [[{
                    "username": "mixed_user",
                    "group_id": "test_group",
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "X-Consumer-Plugin": "direct"
                            }
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/consumers/mixed_user/credentials/cred-mixed',
                ngx.HTTP_PUT,
                [[{
                    "id": "cred-mixed",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-mixed"
                        }
                    }
                }]]
            )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: verify both consumer and group plugins apply together
--- request
GET /hello
--- more_headers
apikey: auth-mixed
--- response_headers
X-Consumer-Plugin: direct
--- response_body
hello world



=== TEST 11: verify group rate limit applies with mixed config
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- First 2 should succeed
            for i = 1, 2 do
                local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                    "/hello", {
                        method = "GET",
                        headers = {
                            ["apikey"] = "auth-mixed"
                        }
                    }
                )

                    if not res or res.status ~= 200 then
                        ngx.say("request ", i, " failed")
                        return
                    end
            end

            -- 3rd should fail
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-mixed"
                    }
                }
            )

            if res.status == 429 then
                ngx.say("rate limiting works correctly")
            else
                ngx.say("expected 429, got: ", res.status)
            end
        }
    }
--- response_body
rate limiting works correctly



=== TEST 12: setup consumer with direct limit-count that overrides group config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers/override_user',
                ngx.HTTP_PUT,
                [[{
                    "username": "override_user",
                    "group_id": "test_group",
                    "plugins": {
                        "limit-count": {
                            "count": 5,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "policy": "local"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/consumers/override_user/credentials/cred-override',
                ngx.HTTP_PUT,
                [[{
                    "id": "cred-override",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-override"
                        }
                    }
                }]]
            )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: verify consumer direct plugin overrides group plugin
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- should allow 5 requests instead of 2
            for i = 1, 5 do
                local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                    "/hello", {
                        method = "GET",
                        headers = {
                            ["apikey"] = "auth-override"
                        }
                    }
                )

                if not res then
                    ngx.say("request ", i, " failed: ", err)
                    return
                end

                if res.status ~= 200 then
                    ngx.say("request ", i, " unexpected status: ", res.status)
                    return
                end
            end

            -- 6th request should be rate limited
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port ..
                "/hello", {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-override"
                    }
                }
            )

            if res.status == 429 then
                ngx.say("consumer plugin overrides group plugin correctly")
            else
                ngx.say("expected 429, got: ", res.status)
            end
        }
    }
--- response_body
consumer plugin overrides group plugin correctly



=== TEST 14: cleanup
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            t('/apisix/admin/consumers/jack', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/jane', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/mixed_user', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/override_user', ngx.HTTP_DELETE)

            t('/apisix/admin/consumer_groups/test_group', ngx.HTTP_DELETE)
            t('/apisix/admin/consumer_groups/premium_group', ngx.HTTP_DELETE)

            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

            ngx.say("cleanup completed")
        }
    }
--- response_body
cleanup completed
