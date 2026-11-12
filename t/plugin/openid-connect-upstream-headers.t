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

=== TEST 1: schema rejects malformed upstream_headers
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local function conf(upstream_headers)
                return {
                    client_id = "apisix",
                    discovery = "http://127.0.0.1:1980/discovery",
                    bearer_only = true,
                    use_jwks = true,
                    upstream_headers = upstream_headers,
                }
            end

            for _, case in ipairs({
                { name = "valid", value = {{header = "X-Client-Id", path = {"azp"}}} },
                { name = "empty list", value = {} },
                { name = "missing path", value = {{header = "X-Client-Id"}} },
                { name = "empty path", value = {{header = "X-Client-Id", path = {}}} },
                { name = "empty key", value = {{header = "X-Client-Id", path = {""}}} },
                { name = "missing header", value = {{path = {"azp"}}} },
                { name = "bad header name", value = {{header = "X Client", path = {"azp"}}} },
            }) do
                local ok, err = plugin.check_schema(conf(case.value))
                ngx.say(case.name, ": ", ok and "ok" or err)
            end
        }
    }
--- response_body
valid: ok
empty list: property "upstream_headers" validation failed: expect array to have at least 1 items
missing path: property "upstream_headers" validation failed: failed to validate item 1: property "path" is required
empty path: property "upstream_headers" validation failed: failed to validate item 1: property "path" validation failed: expect array to have at least 1 items
empty key: property "upstream_headers" validation failed: failed to validate item 1: property "path" validation failed: failed to validate item 1: string too short, expected at least 1, got 0
missing header: property "upstream_headers" validation failed: failed to validate item 1: property "header" is required
bad header name: property "upstream_headers" validation failed: failed to validate item 1: property "header" validation failed: failed to match pattern "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$" with "X Client"



=== TEST 2: claim lookup and serialization
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.openid-connect")

            local claims = core.json.decode([[{
                "https://platform.example.com/claims/identity/profile/id": "p-1",
                "a.b": "dotted",
                "azp": "client-a",
                "scope": "read write",
                "scp": ["read", "write"],
                "org": {"id": "42", "tags": {"tier": "gold"}},
                "age": 30,
                "big": 1700000000123,
                "ratio": 0.5,
                "admin": true,
                "verified": false,
                "roles": [{"name": "a"}],
                "empty_array": [],
                "empty_object": {},
                "nothing": null
            }]])

            local values = plugin._upstream_header_values({
                {header = "X-Profile-Id",
                 path = {"https://platform.example.com/claims/identity/profile/id"}},
                {header = "X-Dotted", path = {"a.b"}},
                {header = "X-Client-Id", path = {"azp"}},
                {header = "X-Scope", path = {"scope"}},
                {header = "X-Scp", path = {"scp"}},
                {header = "X-Org-Id", path = {"org", "id"}},
                {header = "X-Org-Tags", path = {"org", "tags"}},
                {header = "X-Age", path = {"age"}},
                {header = "X-Big", path = {"big"}},
                {header = "X-Ratio", path = {"ratio"}},
                {header = "X-Admin", path = {"admin"}},
                {header = "X-Verified", path = {"verified"}},
                {header = "X-Roles", path = {"roles"}},
                {header = "X-Empty-Array", path = {"empty_array"}},
                {header = "X-Empty-Object", path = {"empty_object"}},
                {header = "X-Null", path = {"nothing"}},
                {header = "X-Missing", path = {"missing"}},
                {header = "X-Too-Deep", path = {"azp", "x"}},
            }, {claims})

            local keys = {}
            for k in pairs(values) do
                table.insert(keys, k)
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                ngx.say(k, ": ", values[k])
            end
        }
    }
--- response_body
X-Admin: true
X-Age: 30
X-Big: 1700000000123
X-Client-Id: client-a
X-Dotted: dotted
X-Empty-Array: e30=
X-Empty-Object: e30=
X-Org-Id: 42
X-Org-Tags: eyJ0aWVyIjoiZ29sZCJ9
X-Profile-Id: p-1
X-Ratio: 0.5
X-Roles: W3sibmFtZSI6ImEifV0=
X-Scope: read write
X-Scp: WyJyZWFkIiwid3JpdGUiXQ==



=== TEST 3: the first claim source holding the claim wins, null and false count as missing
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.openid-connect")
            local id_token = core.json.decode([[{
                "email": "old@example.com",
                "admin": false,
                "role": null,
                "verified": false
            }]])
            local userinfo = core.json.decode([[{
                "email": "new@example.com",
                "phone": "123",
                "admin": true,
                "role": "editor",
                "verified": false
            }]])

            local values = plugin._upstream_header_values({
                {header = "X-Email", path = {"email"}},
                {header = "X-Phone", path = {"phone"}},
                {header = "X-Missing", path = {"missing"}},
                {header = "X-Admin", path = {"admin"}},
                {header = "X-Role", path = {"role"}},
                {header = "X-Verified", path = {"verified"}},
            }, {id_token, userinfo})

            ngx.say("email: ", values["X-Email"])
            ngx.say("phone: ", values["X-Phone"])
            ngx.say("missing: ", values["X-Missing"])
            ngx.say("admin: ", values["X-Admin"])
            ngx.say("role: ", values["X-Role"])
            ngx.say("verified: ", values["X-Verified"])
        }
    }
--- response_body
email: old@example.com
phone: 123
missing: nil
admin: true
role: editor
verified: nil



=== TEST 4: set up a bearer_only route mapping claims to upstream headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local f = assert(io.open("t/certs/public.pem"))
            local public_key = f:read("*a")
            f:close()

            local ns = "https://platform.example.com/claims/identity/profile/"
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, json.encode({
                uri = "/uri",
                plugins = {
                    ["openid-connect"] = {
                        client_id = "apisix",
                        -- never fetched: valid_issuers is configured explicitly
                        discovery = "http://127.0.0.1:1980/discovery-unavailable",
                        bearer_only = true,
                        public_key = public_key,
                        token_signing_alg_values_expected = "RS256",
                        unauth_action = "deny",
                        set_access_token_header = false,
                        set_userinfo_header = false,
                        claim_validator = {
                            issuer = { valid_issuers = {"https://example.com/issuer"} },
                        },
                        upstream_headers = {
                            {header = "X-Claim-Profile-Id", path = {ns .. "id"}},
                            {header = "X-Claim-Email", path = {ns .. "email"}},
                            {header = "X-Claim-Session-Id", path = {ns .. "session/id"}},
                            {header = "X-Claim-User-Type", path = {ns .. "user-type"}},
                            {header = "X-Claim-Client-Id", path = {"azp"}},
                            {header = "X-Claim-Client-Scopes", path = {"scope"}},
                            {header = "X-Claim-Org-Id", path = {"org", "id"}},
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



=== TEST 5: verified claims reach the upstream, spoofed headers never do
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local http = require("resty.http")
            local f = assert(io.open("t/certs/private.pem"))
            local private_key = f:read("*a")
            f:close()

            local ns = "https://platform.example.com/claims/identity/profile/"
            local function token(extra)
                local payload = {
                    iss = "https://example.com/issuer",
                    sub = "jack",
                    exp = ngx.time() + 3600,
                    iat = ngx.time(),
                    azp = "client-a",
                    scope = "read write",
                    [ns .. "id"] = "profile-1",
                    [ns .. "email"] = "jack@example.com",
                }
                for k, v in pairs(extra) do
                    payload[k] = v
                end
                return jwt:sign(private_key, {
                    header = { typ = "JWT", alg = "RS256" },
                    payload = payload,
                })
            end

            local spoofed = {
                ["X-Claim-Profile-Id"] = "spoofed",
                ["X-Claim-Email"] = "spoofed",
                ["X-Claim-Session-Id"] = "spoofed",
                ["X-Claim-User-Type"] = "spoofed",
                ["X-Claim-Client-Id"] = "spoofed",
                ["X-Claim-Client-Scopes"] = "spoofed",
                ["X-Claim-Org-Id"] = "spoofed",
            }

            for _, case in ipairs({
                { name = "all claims", tok = token({
                    [ns .. "session/id"] = "session-1",
                    [ns .. "user-type"] = "internal",
                    org = { id = 42 },
                }) },
                { name = "missing claims", tok = token({}) },
                { name = "no token" },
                { name = "invalid token", tok = "invalid" },
            }) do
                local headers = {}
                for k, v in pairs(spoofed) do
                    headers[k] = v
                end
                if case.tok then
                    headers["Authorization"] = "Bearer " .. case.tok
                end

                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/uri", {
                    method = "GET",
                    headers = headers,
                })
                ngx.say(case.name, ": ", res.status)
                if res.status == 200 then
                    for line in res.body:gmatch("[^\n]+") do
                        if line:find("^x%-claim%-") then
                            ngx.say("  ", line)
                        end
                    end
                end
            end
        }
    }
--- response_body
all claims: 200
  x-claim-client-id: client-a
  x-claim-client-scopes: read write
  x-claim-email: jack@example.com
  x-claim-org-id: 42
  x-claim-profile-id: profile-1
  x-claim-session-id: session-1
  x-claim-user-type: internal
missing claims: 200
  x-claim-client-id: client-a
  x-claim-client-scopes: read write
  x-claim-email: jack@example.com
  x-claim-profile-id: profile-1
no token: 401
invalid token: 401
--- error_log
No bearer token found in request



=== TEST 6: set up a route letting unauthenticated requests pass
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local f = assert(io.open("t/certs/public.pem"))
            local public_key = f:read("*a")
            f:close()

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, json.encode({
                uri = "/uri",
                plugins = {
                    ["openid-connect"] = {
                        client_id = "apisix",
                        client_secret = "secret",
                        -- never fetched: valid_issuers is configured explicitly
                        discovery = "http://127.0.0.1:1980/discovery-unavailable",
                        public_key = public_key,
                        token_signing_alg_values_expected = "RS256",
                        unauth_action = "pass",
                        set_access_token_header = false,
                        set_userinfo_header = false,
                        session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                        claim_validator = {
                            issuer = { valid_issuers = {"https://example.com/issuer"} },
                        },
                        upstream_headers = {
                            {header = "X-Claim-Client-Id", path = {"azp"}},
                            {header = "X-Claim-Client-Scopes", path = {"scope"}},
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



=== TEST 7: passed-through requests carry no declared header, authenticated ones do
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
                    iss = "https://example.com/issuer",
                    sub = "jack",
                    exp = ngx.time() + 3600,
                    iat = ngx.time(),
                    azp = "client-a",
                    scope = {"read", "write"},
                },
            })

            for _, case in ipairs({
                { name = "anonymous" },
                { name = "authenticated", tok = tok },
            }) do
                local headers = {
                    ["X-Claim-Client-Id"] = "spoofed",
                    ["X-Claim-Client-Scopes"] = "spoofed",
                }
                if case.tok then
                    headers["Authorization"] = "Bearer " .. case.tok
                end

                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/uri", {
                    method = "GET",
                    headers = headers,
                })
                ngx.say(case.name, ": ", res.status)
                for line in res.body:gmatch("[^\n]+") do
                    if line:find("^x%-claim%-") then
                        ngx.say("  ", line)
                    end
                end
            end
        }
    }
--- response_body
anonymous: 200
authenticated: 200
  x-claim-client-id: client-a
  x-claim-client-scopes: WyJyZWFkIiwid3JpdGUiXQ==



=== TEST 8: set up a session route mapping ID token claims to upstream headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/*",
                "plugins": {
                    "openid-connect": {
                        "client_id": "apisix",
                        "client_secret": "secret",
                        "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                        "redirect_uri": "http://127.0.0.1:1984/authenticated",
                        "ssl_verify": false,
                        "session": { "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                        "upstream_headers": [
                            { "header": "X-Oidc-User", "path": ["preferred_username"] },
                            { "header": "X-Oidc-Missing", "path": ["no_such_claim"] }
                        ]
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:1980": 1 }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: a logged-in session forwards its claims and drops spoofed headers
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "jack", "jack")
            if not res then
                ngx.say(err)
                return
            end

            local location = res.headers['Location']
            if location:sub(1, 1) == "/" then
                location = "http://127.0.0.1:" .. ngx.var.server_port .. location
            end

            local httpc = http.new()
            res, err = httpc:request_uri(location, {
                method = "GET",
                headers = {
                    ["Cookie"] = concatenate_cookies(res.headers['Set-Cookie']),
                    ["X-Oidc-User"] = "spoofed",
                    ["X-Oidc-Missing"] = "spoofed",
                },
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
            for line in res.body:gmatch("[^\n]+") do
                if line:find("^x%-oidc%-") then
                    ngx.say(line)
                end
            end
        }
    }
--- response_body
200
x-oidc-user: jack
