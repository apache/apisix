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

=== TEST 1: request signing pipeline filters and rewrites requests
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local request = require("apisix.plugins.xml-signer.request")

            local original = {
                get_method = ngx.req.get_method,
                get_headers = ngx.req.get_headers,
                set_body_data = ngx.req.set_body_data,
                headers = core.request.headers,
                get_body = core.request.get_body,
                set_header = core.request.set_header,
            }
            local method = "POST"
            local content_type = " Application/XML ; charset=\"UTF-8\""
            local content_encoding = "IDENTITY"
            local body = "<root/>"
            local body_err
            local body_err_code
            local rewritten_body
            local cleared_headers = {}
            local truncate_content_encoding = false

            ngx.req.get_method = function()
                return method
            end
            ngx.req.get_headers = function(max_headers)
                assert(max_headers == 0)
                local headers = {}
                for i = 1, 101 do
                    headers["x-test-header-" .. i] = "value"
                end
                headers["content-type"] = content_type
                headers["content-encoding"] = content_encoding
                return headers
            end
            ngx.req.set_body_data = function(value)
                rewritten_body = value
            end
            core.request.headers = function()
                local headers = {
                    ["content-type"] = content_type,
                }
                if not truncate_content_encoding then
                    headers["content-encoding"] = content_encoding
                end
                return headers
            end
            core.request.get_body = function()
                return body, body_err, body_err_code
            end
            core.request.set_header = function(ctx, name, value)
                ctx[name] = value
                if value == nil then
                    cleared_headers[name] = true
                end
            end

            local ok, err = pcall(function()
                local ctx = {}
                local sign_calls = 0
                local sign_charset
                local function sign(value, _, charset)
                    sign_calls = sign_calls + 1
                    sign_charset = charset
                    return value .. "-signed"
                end
                local conf = {
                    request = {
                        methods = {"POST"},
                        content_types = {"application/xml"},
                        max_body_bytes = 1024,
                        require_consumer = false,
                    },
                    signature = {algorithm = "rsa-sha256"},
                }

                assert(request.rewrite("xml-signer", conf, ctx, sign) == nil)
                assert(sign_calls == 1)
                assert(sign_charset == "UTF-8")
                assert(rewritten_body == "<root/>-signed")
                assert(ctx["Content-Length"] == tostring(#rewritten_body))
                assert(cleared_headers["Transfer-Encoding"])
                for _, name in ipairs({
                    "Content-MD5", "Digest", "Content-Digest", "Repr-Digest",
                }) do
                    assert(cleared_headers[name])
                end

                content_type = "application/xml"
                content_encoding = "gzip"
                truncate_content_encoding = true
                local status = request.rewrite("xml-signer", conf, {}, sign)
                assert(status == 415)
                assert(sign_calls == 1)

                content_encoding = nil
                truncate_content_encoding = false
                method = "GET"
                assert(request.rewrite("xml-signer", conf, {}, sign) == nil)
                assert(sign_calls == 1)

                method = "POST"
                content_type = nil
                assert(request.rewrite("xml-signer", conf, {}, sign) == 415)
                for _, value in ipairs({
                    false, {"application/xml", "application/xml"},
                }) do
                    content_type = value
                    local status = request.rewrite("xml-signer", conf, {}, sign)
                    assert(status == 415)
                    assert(sign_calls == 1)
                end

                content_type = "application/xml"
                for _, value in ipairs({"gzip", {"identity", "identity"}}) do
                    content_encoding = value
                    assert(request.rewrite("xml-signer", conf, {}, sign) == 415)
                    assert(sign_calls == 1)
                end
                content_encoding = nil

                content_type = "text/plain"
                local status, response = request.rewrite(
                    "xml-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml; charset=iso-8859-1"
                status, response = request.rewrite(
                    "xml-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml; charset=utf-8; charset=iso-8859-1"
                status, response = request.rewrite(
                    "xml-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml"
                body = nil
                body_err = "request size 2048 is greater than the maximum size 1024 allowed"
                body_err_code = "too_large"
                status, response = request.rewrite("xml-signer", conf, {}, sign)
                assert(status == 413)
                assert(response.message == "body_too_large")
                assert(sign_calls == 1)

                body_err = "failed to read request body"
                body_err_code = nil
                status, response = request.rewrite("xml-signer", conf, {}, sign)
                assert(status == 500)
                assert(response.message == "internal_error")
                assert(sign_calls == 1)

                body_err = nil
                status, response = request.rewrite("xml-signer", conf, {}, sign)
                assert(status == 400)
                assert(response.message == "empty_body")
                assert(sign_calls == 1)

                body = ""
                status, response = request.rewrite("xml-signer", conf, {}, sign)
                assert(status == 400)
                assert(response.message == "empty_body")
                assert(sign_calls == 1)

                body = string.rep("x", 1024)
                status, response = request.rewrite("xml-signer", conf, {}, function()
                    return nil, "signing_error", "test signing failure"
                end)
                assert(status == 500)
                assert(response.message == "signing_error")

                status, response = request.rewrite("xml-signer", conf, {}, function()
                    return nil, "credential_error", "test credential failure"
                end)
                assert(status == 500)
                assert(response.message == "credential_error")

                status, response = request.rewrite("xml-signer", conf, {}, function()
                    return nil, "invalid_xml", "test parse failure"
                end)
                assert(status == 400)
                assert(response.message == "invalid_xml")

                status, response = request.rewrite("xml-signer", conf, {}, function()
                    return nil
                end)
                assert(status == 500)
                assert(response.message == "internal_error")

                assert(request.rewrite("xml-signer", conf, {}, sign) == nil)
                assert(sign_calls == 2)
                assert(sign_charset == nil)
            end)

            ngx.req.get_method = original.get_method
            ngx.req.get_headers = original.get_headers
            ngx.req.set_body_data = original.set_body_data
            core.request.headers = original.headers
            core.request.get_body = original.get_body
            core.request.set_header = original.set_header
            assert(ok, err)
            ngx.say("request pipeline verified")
        }
    }
--- request
GET /t
--- response_body
request pipeline verified
--- error_log
xml-signer failed to read request body: request size 2048 is greater than the maximum size 1024 allowed
xml-signer failed to read request body: failed to read request body
xml-signer failed to read request body: nil
xml-signer rejected request: signing_error: test signing failure
xml-signer rejected request: credential_error: test credential failure
xml-signer rejected request: invalid_xml: test parse failure
xml-signer rejected request: nil: nil



=== TEST 2: reload XML bindings and cache resolved credentials
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local credentials = require("apisix.plugins.xml-signer.credentials")
            local module_name = "apisix.plugins.xml-signer.xml"
            for _ = 1, 2 do
                package.loaded[module_name] = nil
                local xml = require(module_name)
                local doc = assert(xml.parse("<root/>"))
                assert(xml.name(xml.root(doc)) == "root")
                xml.free_document(doc)
            end

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }
            local first = assert(credentials.load(conf))
            assert(credentials.load(conf) == first)
            local rotated = assert(credentials.load({
                certificate = read("t/certs/test2.crt"),
                private_key = read("t/certs/test2.key"),
            }))
            assert(rotated ~= first)

            local runtime, err = credentials.load({
                certificate = "$env://UNRESOLVED",
                private_key = conf.private_key,
            })
            assert(runtime == nil)
            assert(err == "credential secret reference could not be resolved")

            runtime, err = credentials.load({
                certificate = read("t/certs/apisix_ecc.crt"),
                private_key = conf.private_key,
            })
            assert(runtime == nil)
            assert(err:find("private key does not match certificate", 1, true))
            ngx.say("reload and credentials verified")
        }
    }
--- request
GET /t
--- response_body
reload and credentials verified



=== TEST 3: normalize defaults without mutating resolved configuration
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.xml-signer")
            local request = require("apisix.plugins.xml-signer.request")
            local original = request.rewrite
            local input = {
                credentials = {certificate = "unused", private_key = "unused"},
            }
            request.rewrite = function(name, conf)
                assert(name == "xml-signer")
                assert(conf ~= input and conf.credentials ~= input.credentials)
                assert(conf.signature.algorithm == "rsa-sha256")
                assert(conf.signature.key_info == "x509_data")
                assert(conf.request.methods[1] == "POST")
                assert(conf.request.content_types[2] == "text/xml")
                assert(conf.request.max_body_bytes == 5242880)
                assert(conf.request.require_consumer == true)
                return 207
            end
            local ok, err = pcall(function()
                assert(plugin.rewrite(input, {}) == 207)
            end)
            request.rewrite = original
            assert(ok, err)
            assert(input.signature == nil and input.request == nil)
            ngx.say("defaults verified")
        }
    }
--- request
GET /t
--- response_body
defaults verified



=== TEST 4: keep the Plugin loadable and reject requests when libxml2 is missing
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local modules = {
                "apisix.plugins.xml-signer",
                "apisix.plugins.xml-signer.signer",
                "apisix.plugins.xml-signer.xml",
            }
            local saved = {}
            for _, name in ipairs(modules) do
                saved[name] = package.loaded[name]
                package.loaded[name] = nil
            end
            -- simulate an image without libxml2
            package.preload["apisix.plugins.xml-signer.xml"] = function()
                error("libxml2 is not available, install the libxml2 package "
                      .. "(for example `apt-get install -y libxml2`): "
                      .. "libxml2.so.2: cannot open shared object file", 0)
            end

            local ok, err = pcall(function()
                local plugin = require("apisix.plugins.xml-signer")
                local status, body = plugin.rewrite({
                    credentials = {certificate = "unused", private_key = "unused"},
                }, {consumer = {username = "client"}})
                ngx.say(status, " ", body.message)
            end)

            package.preload["apisix.plugins.xml-signer.xml"] = nil
            for _, name in ipairs(modules) do
                package.loaded[name] = saved[name]
            end
            assert(ok, err)
        }
    }
--- request
POST /t
<order xmlns="urn:test"><id>42</id></order>
--- more_headers
Content-Type: application/xml
--- response_body
500 signing_error
--- error_log
xml-signer is unavailable and will reject requests: libxml2 is not available
xml-signer rejected request: signing_error: libxml2 is not available



=== TEST 5: require an authenticated Consumer unless explicitly disabled
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local request = require("apisix.plugins.xml-signer.request")
            local function sign()
                error("must not be reached")
            end
            local function conf(require_consumer)
                return {
                    request = {
                        methods = {"GET"},
                        content_types = {"application/xml"},
                        max_body_bytes = 1024,
                        require_consumer = require_consumer,
                    },
                    signature = {algorithm = "rsa-sha256"},
                }
            end

            -- this GET has no Content-Type, so a request that passes the
            -- Consumer check stops with 415
            local cases = {
                {"default, no Consumer", conf(nil), {}},
                {"required, no Consumer", conf(true), {}},
                {"required, Consumer", conf(true), {consumer = {username = "client"}}},
                {"disabled, no Consumer", conf(false), {}},
            }
            for _, case in ipairs(cases) do
                local status, body = request.rewrite("xml-signer", case[2], case[3], sign)
                ngx.say(case[1], ": ", status, " ", body.message)
            end
        }
    }
--- request
GET /t
--- response_body
default, no Consumer: 401 unauthorized
required, no Consumer: 401 unauthorized
required, Consumer: 415 unsupported_media_type
disabled, no Consumer: 415 unsupported_media_type
