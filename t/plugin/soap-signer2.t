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

no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sign proxied SOAP requests and leave other requests untouched
--- config
    location /upstream {
        content_by_lua_block {
            local core = require("apisix.core")
            local xml = require("apisix.plugins.soap-signer.xml")
            local signer = require("apisix.plugins.soap-signer.signer")

            local body = core.request.get_body() or ""
            local signatures = 0
            local doc = xml.parse(body)
            if doc then
                signatures = #xml.find_all(
                    assert(xml.root(doc)), signer.namespaces.ds, "Signature")
                xml.free_document(doc)
            end
            local length = tonumber(ngx.var.http_content_length) or 0
            ngx.say("signatures=", signatures, " length_ok=", length == #body)
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local http = require("resty.http")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local code = t.test('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                core.json.encode({
                    username = "soap_signer_client",
                    plugins = {["key-auth"] = {key = "soap-signer-key"}},
                })
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/soap",
                    plugins = {
                        ["key-auth"] = {},
                        ["proxy-rewrite"] = {uri = "/upstream"},
                        ["soap-signer"] = {
                            credentials = {
                                certificate = read("t/certs/server.crt"),
                                private_key = read("t/certs/server.key"),
                            },
                            request = {max_body_bytes = 16384},
                        },
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:" .. ngx.var.server_port] = 1},
                    },
                })
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local function call(method, content_type, body)
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                    {method = method, body = body,
                     headers = {["Content-Type"] = content_type,
                                apikey = "soap-signer-key"}}))
                if res.status == 200 then
                    ngx.print(res.status, " ", res.body)
                else
                    ngx.say(res.status, " ", core.json.decode(res.body).message)
                end
            end

            -- key-auth rejects the request before soap-signer can sign it
            local anonymous = assert(http.new():request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                {method = "POST", body = "<s:Envelope/>",
                 headers = {["Content-Type"] = "text/xml"}}))
            ngx.say(anonymous.status)

            call("POST", "text/xml", '<s:Envelope xmlns:s="'
                 .. 'http://schemas.xmlsoap.org/soap/envelope/">'
                 .. '<s:Body><Ping xmlns="urn:test"/></s:Body></s:Envelope>')
            call("GET", "text/xml")
            call("POST", "application/json", "{}")
            call("POST", "text/xml", "<broken")
            local prefix = '<s:Envelope xmlns:s="'
                .. 'http://schemas.xmlsoap.org/soap/envelope/">'
                .. '<s:Body><Ping xmlns="urn:test">'
            local suffix = "</Ping></s:Body></s:Envelope>"
            local exact = prefix .. string.rep("x", 16384 - #prefix - #suffix) .. suffix
            assert(#exact == 16384)
            call("POST", "text/xml", exact)
            call("POST", "text/xml", exact .. " ")
            call("POST", "text/xml", "")
        }
    }
--- request
GET /t
--- response_body
401
200 signatures=1 length_ok=true
200 signatures=0 length_ok=true
415 unsupported_media_type
400 invalid_soap
200 signatures=1 length_ok=true
413 body_too_large
400 empty_body
--- error_log
soap-signer rejected request: invalid_soap
soap-signer failed to read request body: request size 16385 is greater than the maximum size 16384 allowed
soap-signer failed to read request body: nil



=== TEST 2: enforce the body limit while reading and never raise the operator limit
--- extra_yaml_config
nginx_config:
  http:
    client_max_body_size: 8k
--- config
    location /upstream {
        content_by_lua_block {
            ngx.say("upstream reached")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local http = require("resty.http")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local code = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/soap",
                    plugins = {
                        ["proxy-rewrite"] = {uri = "/upstream"},
                        ["soap-signer"] = {
                            credentials = {
                                certificate = read("t/certs/server.crt"),
                                private_key = read("t/certs/server.key"),
                            },
                            -- the route is not protected by an authentication Plugin
                            request = {max_body_bytes = 16384, require_consumer = false},
                        },
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:" .. ngx.var.server_port] = 1},
                    },
                })
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local prefix = '<s:Envelope xmlns:s="'
                .. 'http://schemas.xmlsoap.org/soap/envelope/"><s:Body><p>'
            local suffix = '</p></s:Body></s:Envelope>'
            local function envelope(size)
                local value = prefix .. string.rep("x", size - #prefix - #suffix)
                              .. suffix
                assert(#value == size)
                return value
            end

            -- the global 8k limit applies although max_body_bytes is 16k
            for _, size in ipairs({8192, 8193}) do
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                    {method = "POST", body = envelope(size),
                     headers = {["Content-Type"] = "text/xml"}}))
                if res.status == 200 then
                    ngx.print(res.status, " ", res.body)
                else
                    ngx.say(res.status, " ", core.json.decode(res.body).message)
                end
            end

            -- a chunked body without Content-Length is cut off while NGINX
            -- reads it; lua-resty-http sends a function body as-is, so the
            -- iterator produces the chunked transfer coding itself
            local chunks = 64
            local done = false
            local res = assert(http.new():request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                {method = "POST",
                 body = function()
                     if done then
                         return nil
                     end
                     if chunks == 0 then
                         done = true
                         return "0\r\n\r\n"
                     end
                     chunks = chunks - 1
                     return string.format("%x\r\n%s\r\n", 4096, string.rep("x", 4096))
                 end,
                 headers = {["Content-Type"] = "text/xml",
                            ["Transfer-Encoding"] = "chunked"}}))
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
200 upstream reached
413 body_too_large
413
--- error_log
soap-signer failed to read request body: request size 8193 is greater than the maximum size 8192 allowed
client intended to send too large chunked body



=== TEST 3: refuse to sign without an authenticated Consumer by default
--- config
    location /upstream {
        content_by_lua_block {
            ngx.say("upstream reached")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local http = require("resty.http")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local code = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/soap",
                    plugins = {
                        ["proxy-rewrite"] = {uri = "/upstream"},
                        ["soap-signer"] = {
                            credentials = {
                                certificate = read("t/certs/server.crt"),
                                private_key = read("t/certs/server.key"),
                            },
                        },
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:" .. ngx.var.server_port] = 1},
                    },
                })
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            for _, method in ipairs({"POST", "GET"}) do
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                    {method = method, body = method == "POST" and "<s:Envelope/>" or nil,
                     headers = {["Content-Type"] = "text/xml"}}))
                ngx.print(method, " ", res.status, " ", res.body)
            end
        }
    }
--- request
GET /t
--- response_body
POST 401 {"message":"unauthorized"}
GET 200 upstream reached
--- error_log
soap-signer rejected request: no authenticated Consumer
