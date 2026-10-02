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

=== TEST 1: validate schema
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.soap-signer")
            local ok = plugin.check_schema({
                credentials = {
                    certificate = "$secret://vault/signing/certificate",
                    private_key = "$secret://vault/signing/private-key",
                },
                soap = {version = "1.2"},
                timestamp = {ttl_seconds = 60},
            })
            ngx.say(ok)

            ok = plugin.check_schema({
                credentials = {
                    certificate = "certificate",
                    private_key = "private-key",
                },
                timestamp = {ttl_seconds = 0},
            })
            ngx.say(ok)

            ok = plugin.check_schema({
                credentials = {
                    certificate = "certificate",
                    private_key = "private-key",
                },
                signature = {algorithm = "rsa-sha1"},
            })
            ngx.say(ok)

            ok = plugin.check_schema({
                credentials = {
                    certificate = "certificate",
                    private_key = "private-key",
                },
                signature = {algorithm = "rsa-sha512"},
            })
            ngx.say(ok)
        }
    }
--- request
GET /t
--- response_body
true
false
true
false



=== TEST 2: sign and verify SOAP 1.1
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.signing.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body><Ping xmlns="urn:test"/></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local signatures = xml.find_all(root, signer.namespaces.ds, "Signature")
            local signed_info = assert(xml.find_child(
                signatures[1], signer.namespaces.ds, "SignedInfo"))
            local references = xml.find_all(
                signed_info, signer.namespaces.ds, "Reference")
            assert(#references == 2)
            assert(#xml.find_all(
                root, signer.namespaces.wsse, "BinarySecurityToken") == 1)

            local function find_by_id(id)
                local found
                xml.walk(root, function(node)
                    if xml.get_namespaced_property(
                        node, signer.namespaces.wsu, "Id") == id then
                        found = node
                    end
                end)
                return found
            end

            for _, reference in ipairs(references) do
                local uri = assert(xml.get_property(reference, "URI"))
                local target = assert(find_by_id(uri:sub(2)))
                local canonical = assert(xml.canonicalize(target))
                local context = assert(digest.new("sha256"))
                assert(context:update(canonical))
                local expected = ngx.encode_base64(assert(context:final()))
                local value = assert(xml.find_child(
                    reference, signer.namespaces.ds, "DigestValue"))
                assert(xml.content(value) == expected)
            end

            local signature_value = assert(xml.find_child(
                signatures[1], signer.namespaces.ds, "SignatureValue"))
            local canonical = assert(xml.canonicalize(signed_info))
            local raw_signature = assert(ngx.decode_base64(xml.content(signature_value)))
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            assert(public_key:verify(raw_signature, canonical, "sha256"))
            xml.free_document(doc)
            ngx.say("verified")
        }
    }
--- request
GET /t
--- response_body
verified



=== TEST 3: sign SOAP 1.2 and reject existing signatures
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.signing.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {
                credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = true},
                timestamp = {ttl_seconds = 300},
            }
            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Header/><s:Body><Ping/></s:Body>
</s:Envelope>]], conf, 1790856000))
            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            assert(#xml.find_all(root, signer.namespaces.ds, "Signature") == 1)
            xml.free_document(doc)

            local _, code = signer.sign(signed, conf, 1790856000)
            ngx.say(code)
        }
    }
--- request
GET /t
--- response_body
already_signed



=== TEST 4: sign and verify SOAP with RSA-SHA1
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.signing.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body><Legacy xmlns="urn:test"/></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                },
                signature = {algorithm = "rsa-sha1"},
                soap = {version = "auto", must_understand = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local signature = assert(xml.find_all(
                root, signer.namespaces.ds, "Signature")[1])
            local signed_info = assert(xml.find_child(
                signature, signer.namespaces.ds, "SignedInfo"))
            local signature_method = assert(xml.find_child(
                signed_info, signer.namespaces.ds, "SignatureMethod"))
            assert(xml.get_property(signature_method, "Algorithm")
                   == signer.namespaces.ds .. "rsa-sha1")

            local references = xml.find_all(
                signed_info, signer.namespaces.ds, "Reference")
            assert(#references == 2)
            for _, reference in ipairs(references) do
                local digest_method = assert(xml.find_child(
                    reference, signer.namespaces.ds, "DigestMethod"))
                assert(xml.get_property(digest_method, "Algorithm")
                       == signer.namespaces.ds .. "sha1")
            end

            local signature_value = assert(xml.find_child(
                signature, signer.namespaces.ds, "SignatureValue"))
            local canonical_signed_info = assert(xml.canonicalize(signed_info))
            local raw_signature = assert(ngx.decode_base64(xml.content(signature_value)))
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            assert(public_key:verify(raw_signature, canonical_signed_info, "sha1"))

            local function find_by_id(id)
                local found
                xml.walk(root, function(node)
                    if xml.get_namespaced_property(
                        node, signer.namespaces.wsu, "Id") == id then
                        found = node
                    end
                end)
                return found
            end

            for _, reference in ipairs(references) do
                local uri = assert(xml.get_property(reference, "URI"))
                local target = assert(find_by_id(uri:sub(2)))
                local canonical = assert(xml.canonicalize(target))
                local context = assert(digest.new("sha1"))
                assert(context:update(canonical))
                local expected = ngx.encode_base64(assert(context:final()))
                local value = assert(xml.find_child(
                    reference, signer.namespaces.ds, "DigestValue"))
                assert(xml.content(value) == expected)
            end

            xml.free_document(doc)
            ngx.say("verified rsa-sha1")
        }
    }
--- request
GET /t
--- response_body
verified rsa-sha1



=== TEST 5: sign SOAP without KeyInfo or BinarySecurityToken
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.signing.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body><Ping/></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                },
                signature = {
                    algorithm = "rsa-sha256",
                    key_info = "none",
                },
                soap = {version = "auto", must_understand = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            assert(#xml.find_all(root, signer.namespaces.ds, "Signature") == 1)
            assert(#xml.find_all(root, signer.namespaces.ds, "Reference") == 2)
            assert(#xml.find_all(root, signer.namespaces.ds, "KeyInfo") == 0)
            assert(#xml.find_all(
                root, signer.namespaces.wsse, "BinarySecurityToken") == 0)
            xml.free_document(doc)
            ngx.say("signed without KeyInfo")
        }
    }
--- request
GET /t
--- response_body
signed without KeyInfo
