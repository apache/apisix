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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set up a route validating tokens locally, audience matched with the client id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local f = assert(io.open("t/certs/public.pem"))
            local public_key = f:read("*a")
            f:close()

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, json.encode({
                uri = "/hello",
                plugins = {
                    ["openid-connect"] = {
                        client_id = "apisix",
                        client_secret = "secret",
                        -- never fetched: valid_issuers is configured explicitly
                        discovery = "http://127.0.0.1:1980/discovery-unavailable",
                        bearer_only = true,
                        public_key = public_key,
                        token_signing_alg_values_expected = "RS256",
                        claim_validator = {
                            issuer = { valid_issuers = {"https://example.com/issuer"} },
                            audience = { match_with_client_id = true },
                        },
                    },
                },
                upstream = {
                    type = "roundrobin",
                    nodes = { ["127.0.0.1:1980"] = 1 },
                },
            }))

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: a token without the audience claim does not satisfy match_with_client_id
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local http = require("resty.http")
            local f = assert(io.open("t/certs/private.pem"))
            local private_key = f:read("*a")
            f:close()

            local function token(aud)
                return jwt:sign(private_key, {
                    header = { typ = "JWT", alg = "RS256" },
                    payload = {
                        iss = "https://example.com/issuer",
                        sub = "jack",
                        aud = aud,
                        exp = ngx.time() + 3600,
                        iat = ngx.time(),
                    },
                })
            end

            for _, case in ipairs({
                { name = "no audience", tok = token(nil) },
                { name = "other audience", tok = token("another-client") },
                { name = "client id as audience", tok = token("apisix") },
            }) do
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello", {
                    method = "GET",
                    headers = { Authorization = "Bearer " .. case.tok },
                })
                ngx.say(case.name, ": ", res and res.status or "request failed")
            end
        }
    }
--- response_body
no audience: 403
other audience: 403
client id as audience: 200
--- error_log
required audience (aud) not present
audience does not match the client id



=== TEST 3: set up a route deriving the trusted issuer from an unreachable discovery document
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local f = assert(io.open("t/certs/public.pem"))
            local public_key = f:read("*a")
            f:close()

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, json.encode({
                uri = "/hello",
                plugins = {
                    ["openid-connect"] = {
                        client_id = "apisix",
                        client_secret = "secret",
                        discovery = "http://127.0.0.1:1980/discovery-unavailable",
                        bearer_only = true,
                        public_key = public_key,
                        token_signing_alg_values_expected = "RS256",
                    },
                },
                upstream = {
                    type = "roundrobin",
                    nodes = { ["127.0.0.1:1980"] = 1 },
                },
            }))

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: a token is rejected while the trusted issuer cannot be determined
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local http = require("resty.http")
            local f = assert(io.open("t/certs/private.pem"))
            local private_key = f:read("*a")
            f:close()

            local tok = jwt:sign(private_key, {
                header = { typ = "JWT", alg = "RS256" },
                payload = {
                    iss = "https://attacker.example.com",
                    sub = "jack",
                    exp = ngx.time() + 3600,
                    iat = ngx.time(),
                },
            })

            local httpc = http.new()
            local res = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. tok },
            })
            ngx.say(res.status)
            ngx.say(res.headers["WWW-Authenticate"])
        }
    }
--- response_body_like
^401
Bearer realm="apisix", error="invalid_token", error_description="issuer validation unavailable"$
--- error_log
OIDC access discovery url failed
