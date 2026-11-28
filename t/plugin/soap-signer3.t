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
            local request = require("apisix.plugins.soap-signer.request")

            local original = {
                get_method = ngx.req.get_method,
                set_body_data = ngx.req.set_body_data,
                get_headers = ngx.req.get_headers,
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

            ngx.req.get_method = function()
                return method
            end
            ngx.req.set_body_data = function(value)
                rewritten_body = value
            end
            -- the Plugin must read every header; more than the default
            -- limit of 100 must not hide Content-Type or Content-Encoding
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
                local function sign(value)
                    sign_calls = sign_calls + 1
                    return value .. "-signed"
                end
                local conf = {
                    request = {
                        methods = {"POST"},
                        content_types = {"Application/XML"},
                        max_body_bytes = 1024,
                        require_consumer = false,
                    },
                    signature = {algorithm = "rsa-sha256"},
                }

                assert(request.rewrite("soap-signer", conf, ctx, sign) == nil)
                assert(sign_calls == 1)
                assert(rewritten_body == "<root/>-signed")
                assert(ctx["Content-Length"] == tostring(#rewritten_body))
                assert(cleared_headers["Transfer-Encoding"])
                for _, name in ipairs({
                    "Content-MD5", "Digest", "Content-Digest", "Repr-Digest",
                }) do
                    assert(cleared_headers[name])
                end

                method = "GET"
                assert(request.rewrite("soap-signer", conf, {}, sign) == nil)
                assert(sign_calls == 1)

                method = "POST"
                content_type = nil
                assert(request.rewrite("soap-signer", conf, {}, sign) == 415)
                for _, value in ipairs({
                    false, {"application/xml", "application/xml"},
                }) do
                    content_type = value
                    local status = request.rewrite("soap-signer", conf, {}, sign)
                    assert(status == 415)
                    assert(sign_calls == 1)
                end

                content_type = "application/xml"
                for _, value in ipairs({"gzip", {"identity", "identity"}}) do
                    content_encoding = value
                    assert(request.rewrite("soap-signer", conf, {}, sign) == 415)
                    assert(sign_calls == 1)
                end
                content_encoding = nil

                content_type = "text/plain"
                local status, response = request.rewrite(
                    "soap-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml; charset=iso-8859-1"
                status, response = request.rewrite(
                    "soap-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml; charset=utf-8; charset=iso-8859-1"
                status, response = request.rewrite(
                    "soap-signer", conf, {}, sign)
                assert(status == 415)
                assert(response.message == "unsupported_media_type")
                assert(sign_calls == 1)

                content_type = "application/xml"
                body = nil
                body_err = "request size 2048 is greater than the maximum size 1024 allowed"
                body_err_code = "too_large"
                status, response = request.rewrite("soap-signer", conf, {}, sign)
                assert(status == 413)
                assert(response.message == "body_too_large")
                assert(sign_calls == 1)

                body_err = "failed to read request body"
                body_err_code = nil
                status, response = request.rewrite("soap-signer", conf, {}, sign)
                assert(status == 500)
                assert(response.message == "internal_error")
                assert(sign_calls == 1)

                body_err = nil
                status, response = request.rewrite("soap-signer", conf, {}, sign)
                assert(status == 400)
                assert(response.message == "empty_body")
                assert(sign_calls == 1)

                body = ""
                status, response = request.rewrite("soap-signer", conf, {}, sign)
                assert(status == 400)
                assert(response.message == "empty_body")
                assert(sign_calls == 1)

                body = string.rep("x", 1024)
                status, response = request.rewrite("soap-signer", conf, {}, function()
                    return nil, "signing_error", "test signing failure"
                end)
                assert(status == 500)
                assert(response.message == "signing_error")

                status, response = request.rewrite("soap-signer", conf, {}, function()
                    return nil, "credential_error", "test credential failure"
                end)
                assert(status == 500)
                assert(response.message == "credential_error")

                status, response = request.rewrite("soap-signer", conf, {}, function()
                    return nil, "invalid_soap", "test parse failure"
                end)
                assert(status == 400)
                assert(response.message == "invalid_soap")

                status, response = request.rewrite("soap-signer", conf, {}, function()
                    return nil
                end)
                assert(status == 500)
                assert(response.message == "internal_error")

                assert(request.rewrite("soap-signer", conf, {}, sign) == nil)
                assert(sign_calls == 2)
            end)

            ngx.req.get_method = original.get_method
            ngx.req.set_body_data = original.set_body_data
            ngx.req.get_headers = original.get_headers
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
soap-signer failed to read request body: request size 2048 is greater than the maximum size 1024 allowed
soap-signer failed to read request body: failed to read request body
soap-signer failed to read request body: nil
soap-signer rejected request: signing_error: test signing failure
soap-signer rejected request: credential_error: test credential failure
soap-signer rejected request: invalid_soap: test parse failure
soap-signer rejected request: nil: nil



=== TEST 2: reload XML bindings and cache resolved credentials
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local credentials = require("apisix.plugins.soap-signer.credentials")
            local module_name = "apisix.plugins.soap-signer.xml"
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



=== TEST 3: verify both SOAP versions with independently constructed canonical forms
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"
            local signature_uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
            local digest_uri = "http://www.w3.org/2001/04/xmlenc#sha256"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local function hash(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end

            local certificate_pem = read("t/certs/server.crt")
            local conf = {
                credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = false},
                timestamp = {ttl_seconds = 300},
            }
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            for _, soap_ns in ipairs({ns.soap11, ns.soap12}) do
                local signed = assert(signer.sign(
                    '<s:Envelope xmlns:s="' .. soap_ns .. '"><s:Body>'
                    .. '<Ping xmlns="urn:test"><Note xmlns="">x</Note></Ping>'
                    .. '</s:Body></s:Envelope>', conf, 1790856000))
                local doc = assert(xml.parse(signed))
                local root = assert(xml.root(doc))
                local body = assert(xml.find_child(root, soap_ns, "Body"))
                local timestamp = assert(xml.find_all(root, ns.wsu, "Timestamp")[1])
                local body_id = assert(xml.get_namespaced_property(body, ns.wsu, "Id"))
                local time_id = assert(xml.get_namespaced_property(
                    timestamp, ns.wsu, "Id"))
                local expected_body = '<s:Body xmlns:s="' .. soap_ns
                    .. '" xmlns:wsu="' .. ns.wsu .. '" wsu:Id="' .. body_id .. '">'
                    .. '<Ping xmlns="urn:test"><Note xmlns="">x</Note></Ping></s:Body>'
                local expected_time = '<wsu:Timestamp xmlns:wsu="' .. ns.wsu
                    .. '" wsu:Id="' .. time_id .. '">'
                    .. '<wsu:Created>2026-10-01T12:00:00Z</wsu:Created>'
                    .. '<wsu:Expires>2026-10-01T12:05:00Z</wsu:Expires>'
                    .. '</wsu:Timestamp>'
                local expected_digests = {hash(expected_body), hash(expected_time)}
                local ids = {body_id, time_id}
                local expected_info = '<ds:SignedInfo xmlns:ds="' .. ns.ds .. '">'
                    .. '<ds:CanonicalizationMethod Algorithm="' .. exclusive
                    .. '"></ds:CanonicalizationMethod><ds:SignatureMethod Algorithm="'
                    .. signature_uri .. '"></ds:SignatureMethod>'
                local signature = assert(xml.find_all(root, ns.ds, "Signature")[1])
                local references = xml.find_all(signature, ns.ds, "Reference")
                assert(#references == 2)
                for index, id in ipairs(ids) do
                    local reference = references[index]
                    assert(xml.get_property(reference, "URI") == "#" .. id)
                    local value = assert(xml.find_child(reference, ns.ds, "DigestValue"))
                    assert(xml.content(value) == expected_digests[index])
                    expected_info = expected_info .. '<ds:Reference URI="#' .. id
                        .. '"><ds:Transforms><ds:Transform Algorithm="' .. exclusive
                        .. '"></ds:Transform></ds:Transforms><ds:DigestMethod Algorithm="'
                        .. digest_uri .. '"></ds:DigestMethod><ds:DigestValue>'
                        .. expected_digests[index]
                        .. '</ds:DigestValue></ds:Reference>'
                end
                expected_info = expected_info .. '</ds:SignedInfo>'
                local value = assert(xml.find_child(signature, ns.ds, "SignatureValue"))
                assert(public_key:verify(
                    assert(ngx.decode_base64(xml.content(value))), expected_info, "sha256"))
                local security = assert(xml.find_all(root, ns.wsse, "Security")[1])
                assert(xml.get_namespaced_property(security, soap_ns, "mustUnderstand")
                       == (soap_ns == ns.soap11 and "0" or "false"))
                local token = assert(xml.find_all(root, ns.wsse, "BinarySecurityToken")[1])
                local token_id = assert(xml.get_namespaced_property(token, ns.wsu, "Id"))
                local key_info = assert(xml.find_child(signature, ns.ds, "KeyInfo"))
                local token_ref = assert(xml.find_all(key_info, ns.wsse, "Reference")[1])
                assert(xml.get_property(token_ref, "URI") == "#" .. token_id)
                xml.free_document(doc)
            end
            ngx.say("independent SOAP canonical forms verified")
        }
    }
--- request
GET /t
--- response_body
independent SOAP canonical forms verified



=== TEST 4: normalize defaults without mutating resolved configuration
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.soap-signer")
            local request = require("apisix.plugins.soap-signer.request")
            assert(plugin.run_policy == "prefer_route")
            local original = request.rewrite
            local input = {
                credentials = {certificate = "unused", private_key = "unused"},
                soap = {must_understand = false},
            }
            request.rewrite = function(name, conf)
                assert(name == "soap-signer")
                assert(conf ~= input and conf.credentials ~= input.credentials)
                assert(conf.signature.algorithm == "rsa-sha256")
                assert(conf.signature.key_info == "binary_security_token")
                assert(conf.soap.version == "auto")
                assert(conf.soap.must_understand == false)
                assert(conf.timestamp.ttl_seconds == 300)
                assert(conf.request.methods[1] == "POST")
                assert(conf.request.content_types[2] == "application/soap+xml")
                assert(conf.request.max_body_bytes == 5242880)
                assert(conf.request.require_consumer == true)
                assert(conf.soap.allow_existing_security_content == false)
                return 207
            end
            local ok, err = pcall(function()
                assert(plugin.rewrite(input, {}) == 207)
            end)
            request.rewrite = original
            assert(ok, err)
            assert(input.signature == nil and input.request == nil and input.timestamp == nil)
            assert(input.soap.version == nil and input.soap.must_understand == false)
            ngx.say("defaults verified")
        }
    }
--- request
GET /t
--- response_body
defaults verified



=== TEST 5: parse many documents without exhausting FFI callback slots
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local xml = require("apisix.plugins.soap-signer.xml")
            -- LuaJIT has a fixed number of FFI callback slots; creating one
            -- per parse fails after about a thousand requests, and calling
            -- back into Lua from a compiled trace raises "bad callback"
            for _ = 1, 5000 do
                local doc = assert(xml.parse("<root/>"))
                xml.free_document(doc)
                local bad, err = xml.parse('<root><p:undeclared/></root>')
                assert(bad == nil and err == "failed to parse XML")
            end
            ngx.say("parsed")
        }
    }
--- request
GET /t
--- response_body
parsed



=== TEST 6: keep the Plugin loadable and reject requests when libxml2 is missing
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local modules = {
                "apisix.plugins.soap-signer",
                "apisix.plugins.soap-signer.signer",
                "apisix.plugins.soap-signer.xml",
            }
            local saved = {}
            for _, name in ipairs(modules) do
                saved[name] = package.loaded[name]
                package.loaded[name] = nil
            end
            -- simulate an image without libxml2
            package.preload["apisix.plugins.soap-signer.xml"] = function()
                error("libxml2 is not available, install the libxml2 package "
                      .. "(for example `apt-get install -y libxml2`): "
                      .. "libxml2.so.2: cannot open shared object file", 0)
            end

            local ok, err = pcall(function()
                local plugin = require("apisix.plugins.soap-signer")
                local status, body = plugin.rewrite({
                    credentials = {certificate = "unused", private_key = "unused"},
                }, {consumer = {username = "client"}})
                ngx.say(status, " ", body.message)
            end)

            package.preload["apisix.plugins.soap-signer.xml"] = nil
            for _, name in ipairs(modules) do
                package.loaded[name] = saved[name]
            end
            assert(ok, err)
        }
    }
--- request
POST /t
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body/></s:Envelope>
--- more_headers
Content-Type: text/xml
--- response_body
500 signing_error
--- error_log
soap-signer is unavailable and will reject requests: libxml2 is not available
soap-signer rejected request: signing_error: libxml2 is not available



=== TEST 7: require an authenticated Consumer unless explicitly disabled
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local request = require("apisix.plugins.soap-signer.request")
            local function sign()
                error("must not be reached")
            end
            local function conf(require_consumer)
                return {
                    request = {
                        methods = {"GET"},
                        content_types = {"text/xml"},
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
                local status, body = request.rewrite("soap-signer", case[2], case[3], sign)
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
