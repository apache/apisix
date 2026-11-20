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
BEGIN {
    $ENV{TEST_HDR_VALUE} = "from-env";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request && !defined $block->exec) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: consumer and routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function put(uri, body)
                local code, res = t(uri, ngx.HTTP_PUT, body)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(res)
                    return false
                end
                return true
            end

            if not put('/apisix/admin/consumers', [[{
                "username": "jack",
                "plugins": {"key-auth": {"key": "auth-jack"}}
            }]]) then return end

            -- route 1: route-level plugin with an $env:// reference
            if not put('/apisix/admin/routes/1', [[{
                "uri": "/uri",
                "host": "env.test",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {"headers": {"add": {"X-Once": "$env://TEST_HDR_VALUE"}}}
                },
                "upstream": {"type": "roundrobin", "nodes": {"127.0.0.1:1980": 1}}
            }]]) then return end

            -- route 2: same plugin with a literal value (control)
            if not put('/apisix/admin/routes/2', [[{
                "uri": "/uri",
                "host": "literal.test",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {"headers": {"add": {"X-Once": "literal"}}}
                },
                "upstream": {"type": "roundrobin", "nodes": {"127.0.0.1:1980": 1}}
            }]]) then return end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: route plugin with $env:// ref runs its rewrite once per request
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            for _, host in ipairs({"literal.test", "env.test"}) do
                for i = 1, 2 do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri, {
                        headers = {Host = host, apikey = "auth-jack"},
                    })
                    if not res then
                        ngx.say(err)
                        return
                    end
                    local line = res.body:match("x%-once: [^\n]*")
                    ngx.say(host, " #", i, " ", line)
                end
            end
        }
    }
--- response_body
literal.test #1 x-once: literal
literal.test #2 x-once: literal
env.test #1 x-once: from-env
env.test #2 x-once: from-env



=== TEST 3: consumer plugin shared by a route that has it and a route that does not
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function put(uri, body)
                local code, res = t(uri, ngx.HTTP_PUT, body)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(res)
                    return false
                end
                return true
            end

            if not put('/apisix/admin/consumers', [[{
                "username": "rose",
                "plugins": {
                    "key-auth": {"key": "auth-rose"},
                    "proxy-rewrite": {"headers": {"add": {"X-Consumer": "rose"}}}
                }
            }]]) then return end

            if not put('/apisix/admin/routes/3', [[{
                "uri": "/uri",
                "host": "with.test",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {"headers": {"add": {"X-Route": "with"}}}
                },
                "upstream": {"type": "roundrobin", "nodes": {"127.0.0.1:1980": 1}}
            }]]) then return end

            if not put('/apisix/admin/routes/4', [[{
                "uri": "/uri",
                "host": "without.test",
                "plugins": {"key-auth": {}},
                "upstream": {"type": "roundrobin", "nodes": {"127.0.0.1:1980": 1}}
            }]]) then return end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 4: route with the plugin first, then route without it
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            for _, host in ipairs({"with.test", "without.test"}) do
                local httpc = http.new()
                local res = httpc:request_uri(uri, {
                    headers = {Host = host, apikey = "auth-rose"},
                })
                ngx.say(host, " route=", res.body:match("x%-route: ([^\n]*)") or "-",
                        " consumer=", res.body:match("x%-consumer: ([^\n]*)") or "-")
            end
        }
    }
--- response_body
with.test route=with consumer=-
without.test route=- consumer=rose



=== TEST 5: route without the plugin first, then route with it
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            for _, host in ipairs({"without.test", "with.test"}) do
                local httpc = http.new()
                local res = httpc:request_uri(uri, {
                    headers = {Host = host, apikey = "auth-rose"},
                })
                ngx.say(host, " route=", res.body:match("x%-route: ([^\n]*)") or "-",
                        " consumer=", res.body:match("x%-consumer: ([^\n]*)") or "-")
            end
        }
    }
--- response_body
without.test route=- consumer=rose
with.test route=with consumer=-



=== TEST 6: store the secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/hdr value=from-vault
--- response_body
Success! Data written to: kv/apisix/hdr



=== TEST 7: route plugin with a $secret:// (vault) reference
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault/test1', ngx.HTTP_PUT, [[{
                "uri": "http://127.0.0.1:8200",
                "prefix": "kv/apisix",
                "token": "root"
            }]])
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/5', ngx.HTTP_PUT, [[{
                "uri": "/uri",
                "host": "secret.test",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {"headers": {"add": {"X-Once": "$secret://vault/test1/hdr/value"}}}
                },
                "upstream": {"type": "roundrobin", "nodes": {"127.0.0.1:1980": 1}}
            }]])
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: route plugin with $secret:// ref runs its rewrite once per request
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            for i = 1, 2 do
                local httpc = http.new()
                local res = httpc:request_uri(uri, {
                    headers = {Host = "secret.test", apikey = "auth-jack"},
                })
                ngx.say("#", i, " ", res.body:match("x%-once: [^\n]*"))
            end
        }
    }
--- response_body
#1 x-once: from-vault
#2 x-once: from-vault
