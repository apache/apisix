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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    # The auth service reports what reached it. Only ngx_http_ffi_client frames
    # a GET with "Content-Length: 0" and sends no User-Agent, which tells the
    # two clients apart.
    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 1986;
        listen 1987 ssl;
        ssl_certificate     cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;

        location /auth {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.header["X-Auth-Content-Length"] = ngx.var.http_content_length or "none"
                ngx.header["X-Auth-Host"] = ngx.var.http_host
                ngx.header["X-Auth-UA"] = ngx.var.http_user_agent
                ngx.header["X-Auth-Method"] = ngx.req.get_method()
                ngx.header["X-Auth-Args"] = ngx.var.args or "none"
                ngx.header["X-Auth-Body"] = ngx.req.get_body_data() or "none"
                ngx.header["X-Auth-Conn-Requests"] = ngx.var.connection_requests
                ngx.header["X-Auth-Connection"] = ngx.var.http_connection or "none"
                ngx.header["X-User-ID"] = "user-1"
                ngx.header["X-Multi"] = {"a", "b"}
                ngx.header["x-lower"] = "l"
                ngx.say("ok")
            }
        }

        location /deny {
            content_by_lua_block {
                ngx.status = 401
                ngx.header["WWW-Authenticate"] = 'Bearer realm="test"'
                ngx.header["X-User-ID"] = "user-1"
                ngx.say("denied")
            }
        }

        location /slow {
            content_by_lua_block {
                ngx.sleep(1)
                ngx.say("ok")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup routes
--- config
    location /t {
        content_by_lua_block {
            local up = {"X-Auth-Content-Length", "X-Auth-Host", "X-Auth-UA", "X-Auth-Method",
                        "X-Auth-Args", "X-Auth-Body", "X-Auth-Conn-Requests",
                        "X-Auth-Connection", "X-User-ID",
                        "X-Multi", "X-Lower", "X-Absent"}
            local echo = {
                phase = "access",
                functions = {
                    [[return function(conf, ctx)
                        local core = require("apisix.core")
                        core.response.exit(200, core.request.headers(ctx))
                    end]]
                }
            }
            local routes = {
                {"fa-ip", {uri = "http://127.0.0.1:1986/auth",
                           request_headers = {"Authorization"}, upstream_headers = up}},
                {"fa-name", {uri = "http://localhost:1986/auth?a=1",
                             upstream_headers = up}},
                {"fa-deny", {uri = "http://127.0.0.1:1986/deny",
                             client_headers = {"WWW-Authenticate"}, upstream_headers = up}},
                {"fa-post", {uri = "http://127.0.0.1:1986/auth", request_method = "POST",
                             upstream_headers = up}},
                {"fa-forwarded-ua", {uri = "http://127.0.0.1:1986/auth",
                                     request_headers = {"User-Agent", "Host"},
                                     upstream_headers = up}},
                {"fa-no-keepalive", {uri = "http://127.0.0.1:1986/auth", keepalive = false,
                                     upstream_headers = up}},
                {"fa-no-keepalive-fwd", {uri = "http://127.0.0.1:1986/auth", keepalive = false,
                                         request_headers = {"connection"},
                                         upstream_headers = up}},
                {"fa-timeout", {uri = "http://127.0.0.1:1986/slow", timeout = 200,
                                upstream_headers = up}},
                {"fa-dns-fail", {uri = "http://forward-auth.invalid:1986/auth",
                                 upstream_headers = up}},
                {"fa-scheme-relative", {uri = "//127.0.0.1:1987/auth", ssl_verify = false,
                                        upstream_headers = up}},
                {"fa-https", {uri = "https://127.0.0.1:1987/auth", ssl_verify = false,
                              upstream_headers = up}},
                {"fa-https-verify", {uri = "https://127.0.0.1:1987/auth",
                                     upstream_headers = up}},
            }

            local t = require("lib.test_admin").test
            for _, r in ipairs(routes) do
                local code, body = t("/apisix/admin/routes/" .. r[1], ngx.HTTP_PUT, {
                    uri = "/" .. r[1],
                    priority = 10,
                    plugins = {
                        ["forward-auth"] = r[2],
                        ["serverless-post-function"] = echo,
                    },
                    upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
                })
                if code >= 300 then
                    ngx.say(r[1], ": ", body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: ngx_http_ffi_client is the default client
--- request
GET /fa-ip
--- more_headers
Authorization: token-1
X-User-ID: injected
X-Absent: injected
--- response_body_like eval
qr/^(?!.*"x-auth-ua")
   (?=.*"x-auth-content-length":"0")
   (?=.*"x-auth-host":"127\.0\.0\.1:1986")
   (?=.*"x-auth-method":"GET")
   (?=.*"x-auth-connection":"keep-alive")
   (?=.*"x-user-id":"user-1")
   (?=.*"x-multi":\["a","b"\])
   (?=.*"x-lower":"l")/sx
--- response_body_unlike
x-absent
--- no_error_log
[error]



=== TEST 3: a hostname is resolved by the APISIX resolver; Host keeps the name and the query is sent
--- request
GET /fa-name
--- response_body_like eval
qr/(?=.*"x-auth-content-length":"0")
   (?=.*"x-auth-host":"localhost:1986")
   (?=.*"x-auth-args":"a=1")
   (?=.*"x-user-id":"user-1")/sx
--- no_error_log
[error]



=== TEST 4: denied requests get the auth status, body and client_headers
--- request
GET /fa-deny
--- error_code: 401
--- response_body
denied
--- response_headers
WWW-Authenticate: Bearer realm="test"
--- no_error_log
[error]



=== TEST 5: POST forwards the request body
--- request
POST /fa-post
hello-body
--- response_body_like eval
qr/(?=.*"x-auth-method":"POST")
   (?=.*"x-auth-body":"hello-body")
   (?=.*"x-auth-content-length":"10")/sx
--- no_error_log
[error]



=== TEST 6: forwarded Host and User-Agent are sent
--- request
GET /fa-forwarded-ua
--- more_headers
Host: client.test
User-Agent: test-client/1.0
--- response_body_like eval
qr/(?=.*"x-auth-content-length":"0")
   (?=.*"x-auth-host":"client\.test")
   (?=.*"x-auth-ua":"test-client\/1\.0")/sx



=== TEST 7: the connection to the auth service is reused
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local seen = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984/fa-ip")
                if not res then
                    ngx.say("request failed: ", err)
                    return
                end
                local headers = require("cjson").decode(res.body)
                seen[i] = tonumber(headers["x-auth-conn-requests"])
            end
            ngx.say(seen[2] == seen[1] + 1 and "reused" or "not reused")
        }
    }
--- response_body
reused



=== TEST 8: keepalive false closes the connection to the auth service
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984/fa-no-keepalive")
                if not res then
                    ngx.say("request failed: ", err)
                    return
                end
                local headers = require("cjson").decode(res.body)
                ngx.say(headers["x-auth-conn-requests"], " ", headers["x-auth-connection"])
            end
        }
    }
--- response_body
1 close
1 close



=== TEST 9: auth service timeout
--- request
GET /fa-timeout
--- error_code: 403
--- error_log
failed to process forward auth, err: timeout



=== TEST 10: auth service name that does not resolve
--- request
GET /fa-dns-fail
--- error_code: 403
--- error_log
failed to process forward auth, err: forward-auth.invalid could not be resolved



=== TEST 11: plugin_attr selects lua-resty-http
--- extra_yaml_config
plugin_attr:
  forward-auth:
    http_client: lua-resty-http
--- request
GET /fa-ip
--- more_headers
Authorization: token-1
--- response_body_like eval
qr/(?=.*"x-auth-content-length":"none")
   (?=.*"x-auth-ua":"lua-resty-http\/[\d.]+[ ]\(Lua\)[ ]ngx_lua\/\d+")
   (?=.*"x-auth-connection":"none")
   (?=.*"x-auth-host":"127\.0\.0\.1:1986")
   (?=.*"x-user-id":"user-1")
   (?=.*"x-multi":\["a","b"\])/sx
--- no_error_log
[error]



=== TEST 12: lua-resty-http resolves hostnames and reports DNS failures
--- extra_yaml_config
plugin_attr:
  forward-auth:
    http_client: lua-resty-http
--- request
GET /fa-dns-fail
--- error_code: 403
--- error_log
failed to process forward auth, err: failed to parse domain



=== TEST 13: an unknown client name fails the request
--- extra_yaml_config
plugin_attr:
  forward-auth:
    http_client: unknown-client
--- request
GET /fa-ip
--- error_code: 403
--- error_log
invalid plugin_attr.forward-auth: property "http_client" validation failed



=== TEST 14: an unavailable ngx_http_ffi_client fails the request instead of switching clients
--- extra_init_by_lua
    package.loaded["resty.ngx_http_ffi_client"] = "not a module"
--- request
GET /fa-ip
--- error_code: 403
--- error_log
resty.ngx_http_ffi_client is not available



=== TEST 15: https endpoint goes through ngx_http_ffi_client
--- request
GET /fa-https
--- response_body_like eval
qr/(?=.*"x-auth-content-length":"0")
   (?=.*"x-auth-host":"127\.0\.0\.1:1987")
   (?=.*"x-user-id":"user-1")/sx
--- no_error_log
[error]



=== TEST 16: ssl_verify rejects an untrusted auth service certificate
--- request
GET /fa-https-verify
--- error_code: 403
--- error_log
failed to process forward auth, err:



=== TEST 17: a scheme-relative uri follows the scheme of each request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/ssls/fa-test", ngx.HTTP_PUT, {
                cert = t.read_file("t/certs/apisix.crt"),
                key = t.read_file("t/certs/apisix.key"),
                sni = "test.com",
            })
            if code >= 300 then
                ngx.say(body)
                return
            end

            local http = require("resty.http")
            -- 1987 speaks TLS only: plain HTTP to it gets a 400
            for _, scheme in ipairs({"http", "https", "http", "https"}) do
                local httpc = http.new()
                local port = scheme == "http" and 1984 or 1994
                local res, err = httpc:request_uri(scheme .. "://127.0.0.1:" .. port
                                                   .. "/fa-scheme-relative",
                                                   {ssl_verify = false,
                                                    ssl_server_name = "test.com"})
                ngx.say(scheme, ": ", res and res.status or err)
            end
        }
    }
--- response_body
http: 400
https: 200
http: 400
https: 200



=== TEST 18: setup a route whose Host comes from a client header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/fa-empty-host", ngx.HTTP_PUT, {
                uri = "/fa-empty-host",
                priority = 10,
                plugins = {
                    ["forward-auth"] = {
                        uri = "http://localhost:1986/auth",
                        extra_headers = {Host = "$http_x_auth_target"},
                        upstream_headers = {"X-Auth-Host"},
                    },
                    ["serverless-post-function"] = {
                        phase = "access",
                        functions = {
                            [[return function(conf, ctx)
                                local core = require("apisix.core")
                                local host = core.request.header(ctx, "X-Auth-Host")
                                core.response.exit(200, "host: " .. tostring(host) .. "\n")
                            end]]
                        }
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.say(code >= 300 and body or "passed")
        }
    }
--- response_body
passed



=== TEST 19: ngx_http_ffi_client replaces an empty Host with the address it dials
--- request
GET /fa-empty-host
--- response_body
host: 127.0.0.1:1986
--- no_error_log
[error]



=== TEST 20: a Host resolved from the client header is sent as is
--- request
GET /fa-empty-host
--- more_headers
X-Auth-Target: auth.example
--- response_body
host: auth.example
--- no_error_log
[error]



=== TEST 21: lua-resty-http sends the empty Host, which the auth service rejects
--- extra_yaml_config
plugin_attr:
  forward-auth:
    http_client: lua-resty-http
--- request
GET /fa-empty-host
--- error_code: 400
--- no_error_log
[error]



=== TEST 22: lua-resty-http with keepalive false sends no Connection header and closes
--- extra_yaml_config
plugin_attr:
  forward-auth:
    http_client: lua-resty-http
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984/fa-no-keepalive")
                if not res then
                    ngx.say("request failed: ", err)
                    return
                end
                local headers = require("cjson").decode(res.body)
                ngx.say(headers["x-auth-conn-requests"], " ", headers["x-auth-connection"])
            end
        }
    }
--- response_body
1 none
1 none



=== TEST 23: keepalive false sends close even when the client Connection header is forwarded
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/fa-no-keepalive-fwd",
                                               {headers = {connection = "keep-alive"}})
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            local headers = require("cjson").decode(res.body)
            ngx.say(headers["x-auth-conn-requests"], " ", headers["x-auth-connection"])
        }
    }
--- response_body
1 close
