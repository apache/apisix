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
            local xml = require("apisix.plugins.soap-signer.xml")

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
            local xml = require("apisix.plugins.soap-signer.xml")

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
            local xml = require("apisix.plugins.soap-signer.xml")

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
            local xml = require("apisix.plugins.soap-signer.xml")

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



=== TEST 6: reject malformed SOAP envelopes
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")

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
            local function envelope(children)
                return '<s:Envelope xmlns:s="' .. signer.namespaces.soap11 .. '">'
                       .. children .. "</s:Envelope>"
            end

            local bodies = {
                envelope("<s:Body/><s:Header/>"),
                envelope("<s:Body/><s:Body/>"),
                envelope("<s:Header/><s:Header/><s:Body/>"),
                envelope("<s:Header/>"),
                '<!DOCTYPE s:Envelope [<!ENTITY x "y">]>' .. envelope("<s:Body/>"),
                envelope('<s:Body xmlns:wsu="' .. signer.namespaces.wsu
                         .. '" wsu:Id="duplicate"><Ping xml:id="duplicate"/>'
                         .. "</s:Body>"),
                envelope('<s:Body xmlns:wsu="' .. signer.namespaces.wsu
                         .. '" xmlns:xenc="http://www.w3.org/2001/04/xmlenc#'
                         .. '" wsu:Id="duplicate"><xenc:EncryptedData '
                         .. 'Id="duplicate"/></s:Body>'),
                envelope('<s:Body xmlns:wsu="' .. signer.namespaces.wsu
                         .. '" wsu:Id="not a valid ID"/>'),
                envelope("<s:Body><ds:Signature/></s:Body>"),
                envelope('<s:Body><wsse:Security/><x xml:space="bogus"/></s:Body>'),
            }
            for _, body in ipairs(bodies) do
                local _, code, err = signer.sign(body, conf, 1790856000)
                ngx.say(code, ": ", err)
            end
        }
    }
--- request
GET /t
--- response_body
invalid_soap: SOAP Header must precede SOAP Body
invalid_soap: exactly one SOAP Body is required
invalid_soap: at most one SOAP Header is allowed
invalid_soap: SOAP Body is required
invalid_soap: DTD and entity declarations are not allowed
invalid_soap: duplicate XML ID
invalid_soap: duplicate XML ID
invalid_soap: invalid XML ID
invalid_soap: failed to parse XML
invalid_soap: failed to parse XML



=== TEST 7: keep a single wsu:Timestamp in a reused Security header
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

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
                -- this test covers reusing a header that already has content
                soap = {version = "auto", must_understand = true,
                        allow_existing_security_content = true},
                timestamp = {ttl_seconds = 300},
            }
            local function envelope(security)
                return string.format([[
<s:Envelope xmlns:s="%s" xmlns:wsse="%s" xmlns:wsu="%s">
  <s:Header><wsse:Security>%s</wsse:Security></s:Header>
  <s:Body><Ping/></s:Body>
</s:Envelope>]], ns.soap11, ns.wsse, ns.wsu, security)
            end

            local _, code, err = signer.sign(envelope([[
<wsu:Timestamp wsu:Id="TS-client">
  <wsu:Created>2026-10-05T00:00:00Z</wsu:Created>
  <wsu:Expires>2026-10-05T00:05:00Z</wsu:Expires>
</wsu:Timestamp>]]), conf, 1790856000)
            ngx.say(code, ": ", err)

            local signed = assert(signer.sign(envelope([[
<wsse:UsernameToken><wsse:Username>user</wsse:Username></wsse:UsernameToken>]]),
                conf, 1790856000))
            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            ngx.say(#xml.find_all(root, ns.wsse, "Security"), " ",
                    #xml.find_all(root, ns.wsse, "UsernameToken"), " ",
                    #xml.find_all(root, ns.wsu, "Timestamp"), " ",
                    #xml.find_all(root, ns.ds, "Signature"))
            xml.free_document(doc)
        }
    }
--- request
GET /t
--- response_body
invalid_soap: wsse:Security already contains a wsu:Timestamp
1 1 1 1



=== TEST 8: canonicalize default-namespaced Body content as external verifiers do
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body><Ping xmlns="urn:test"><Item>1</Item><Note xmlns="">x</Note></Ping></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local body = assert(xml.find_child(root, ns.soap11, "Body"))
            local body_id = assert(xml.get_namespaced_property(body, ns.wsu, "Id"))

            -- Exclusive C14N of the Body, written out by hand.
            local expected = '<s:Body xmlns:s="' .. ns.soap11 .. '" xmlns:wsu="' .. ns.wsu
                             .. '" wsu:Id="' .. body_id .. '">'
                             .. '<Ping xmlns="urn:test"><Item>1</Item><Note xmlns="">x</Note></Ping>'
                             .. "</s:Body>"
            local context = assert(digest.new("sha256"))
            assert(context:update(expected))
            local expected_digest = ngx.encode_base64(assert(context:final()))

            local actual_digest
            for _, reference in ipairs(xml.find_all(root, ns.ds, "Reference")) do
                if xml.get_property(reference, "URI") == "#" .. body_id then
                    actual_digest = xml.content(assert(xml.find_child(
                        reference, ns.ds, "DigestValue")))
                end
            end
            xml.free_document(doc)
            ngx.say(actual_digest == expected_digest)
        }
    }
--- request
GET /t
--- response_body
true



=== TEST 9: select only an unambiguous ultimate-receiver Security header
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

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
            local soap11 = assert(signer.sign([[<s:Envelope
 xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
 <s:Header><wsse:Security s:actor="urn:intermediary"/><wsse:Security/></s:Header>
 <s:Body><Ping/></s:Body></s:Envelope>]], conf, 1790856000))
            local doc = assert(xml.parse(soap11))
            local root = assert(xml.root(doc))
            local security = xml.find_all(root, ns.wsse, "Security")
            assert(#security == 2)
            assert(#xml.find_all(security[1], ns.ds, "Signature") == 0)
            assert(#xml.find_all(security[2], ns.ds, "Signature") == 1)
            xml.free_document(doc)

            local soap12 = assert(signer.sign([[<s:Envelope
 xmlns:s="http://www.w3.org/2003/05/soap-envelope"
 xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
 <s:Header><wsse:Security s:role="http://www.w3.org/2003/05/soap-envelope/role/next"/>
 <wsse:Security s:role="http://www.w3.org/2003/05/soap-envelope/role/none"/>
 <wsse:Security s:role="http://www.w3.org/2003/05/soap-envelope/role/ultimateReceiver"/></s:Header>
 <s:Body><Ping/></s:Body></s:Envelope>]], conf, 1790856000))
            doc = assert(xml.parse(soap12))
            root = assert(xml.root(doc))
            security = xml.find_all(root, ns.wsse, "Security")
            assert(#security == 3)
            assert(#xml.find_all(security[1], ns.ds, "Signature") == 0)
            assert(#xml.find_all(security[2], ns.ds, "Signature") == 0)
            assert(#xml.find_all(security[3], ns.ds, "Signature") == 1)
            xml.free_document(doc)

            local _, code, err = signer.sign([[<s:Envelope
 xmlns:s="http://www.w3.org/2003/05/soap-envelope"
 xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
 <s:Header><wsse:Security/><wsse:Security s:role="http://www.w3.org/2003/05/soap-envelope/role/ultimateReceiver"/></s:Header>
 <s:Body><Ping/></s:Body></s:Envelope>]], conf, 1790856000)
            ngx.say(code, ": ", err)
        }
    }
--- request
GET /t
--- response_body
invalid_soap: multiple wsse:Security headers target the ultimate receiver



=== TEST 10: preserve payload namespace bindings when adding security namespaces
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 xmlns:wsse="]] .. ns.wsse .. [[" xmlns:wsu="]] .. ns.wsu .. [["
 xmlns:ds="]] .. ns.ds .. [[">
 <s:Header xmlns:wsse="urn:header-payload">
  <wsse:HeaderPayload/>
  <wsse1:Security xmlns:wsse1="]] .. ns.wsse .. [["
   xmlns:wsse="urn:security-payload" xmlns:wsu="urn:security-payload"
   xmlns:ds="urn:security-payload"><wsse:SecurityPayload/></wsse1:Security>
 </s:Header>
 <s:Body xmlns:wsu="urn:body-payload"><wsu:BodyPayload/></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = true,
                        allow_existing_security_content = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local body = assert(xml.find_child(root, ns.soap11, "Body"))
            local security = assert(xml.find_all(root, ns.wsse, "Security")[1])
            assert(xml.get_namespaced_property(body, ns.wsu, "Id"))
            assert(#xml.find_all(body, "urn:body-payload", "BodyPayload") == 1)
            assert(#xml.find_all(root, "urn:header-payload", "HeaderPayload") == 1)
            assert(#xml.find_all(root, "urn:security-payload", "SecurityPayload") == 1)
            assert(#xml.find_all(security, ns.wsu, "Timestamp") == 1)
            assert(#xml.find_all(root, ns.ds, "Signature") == 1)
            xml.free_document(doc)

            signed = assert(signer.sign([[
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 xmlns:wsse="]] .. ns.wsse .. [[">
 <s:Header xmlns:wsse="urn:header-payload"><wsse:HeaderPayload/></s:Header>
 <s:Body><Ping/></s:Body>
</s:Envelope>]], {
                credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                },
                soap = {version = "auto", must_understand = true,
                        allow_existing_security_content = true},
                timestamp = {ttl_seconds = 300},
            }, 1790856000))
            doc = assert(xml.parse(signed))
            root = assert(xml.root(doc))
            assert(#xml.find_all(root, ns.wsse, "Security") == 1)
            assert(#xml.find_all(root, "urn:header-payload", "HeaderPayload") == 1)
            assert(#xml.find_all(root, ns.ds, "Signature") == 1)
            xml.free_document(doc)
            ngx.say("namespace bindings verified")
        }
    }
--- request
GET /t
--- response_body
namespace bindings verified



=== TEST 11: enforce minimum RSA key size per signature algorithm
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local x509 = require("resty.openssl.x509")
            local credentials = require("apisix.plugins.soap-signer.credentials")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local weak = {
                certificate = read("t/certs/server_1024.crt"),
                private_key = read("t/certs/server_1024.key"),
            }
            local function conf(algorithm)
                return {
                    credentials = weak,
                    signature = {algorithm = algorithm,
                                 key_info = "binary_security_token"},
                    soap = {version = "auto", must_understand = true},
                    timestamp = {ttl_seconds = 300},
                }
            end
            local body = '<s:Envelope xmlns:s="' .. signer.namespaces.soap11
                         .. '"><s:Body><Ping xmlns="urn:legacy"/></s:Body></s:Envelope>'

            -- the default minimum is 2048 bits
            local runtime, err = credentials.load(weak)
            ngx.say(runtime == nil, " ", err)

            -- rsa-sha256 rejects a 1024-bit key
            local signed, code, detail = signer.sign(body, conf("rsa-sha256"), 1790856000)
            ngx.say(signed == nil, " ", code, " ", detail)

            -- rsa-sha1 accepts a 1024-bit key for legacy interoperability
            signed = assert(signer.sign(body, conf("rsa-sha1"), 1790856000))
            local ds = signer.namespaces.ds
            local doc = assert(xml.parse(signed))
            local signature = assert(xml.find_all(xml.root(doc), ds, "Signature")[1])
            local signed_info = assert(xml.find_child(signature, ds, "SignedInfo"))
            local value = assert(xml.find_child(signature, ds, "SignatureValue"))
            local public_key = assert(assert(x509.new(weak.certificate, "PEM")):get_pubkey())
            ngx.say("rsa-sha1 1024-bit verified: ", (public_key:verify(
                assert(ngx.decode_base64(xml.content(value))),
                assert(xml.canonicalize(signed_info)), "sha1")))
            xml.free_document(doc)

            -- the cached key pair is checked again for every minimum
            runtime, err = credentials.load(weak, 2048)
            ngx.say(runtime == nil, " ", err)
        }
    }
--- request
GET /t
--- response_body
true RSA private key must be at least 2048 bits
true credential_error RSA private key must be at least 2048 bits
rsa-sha1 1024-bit verified: true
true RSA private key must be at least 2048 bits



=== TEST 12: reject documents that make libxml2 parsing super-linear
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")

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
            local function envelope(attributes, body)
                return '<s:Envelope xmlns:s="' .. signer.namespaces.soap11 .. '"'
                       .. attributes .. '><s:Body>' .. (body or "") .. '</s:Body></s:Envelope>'
            end
            local function decoy_prefixes(n)
                -- occupy ds, ds1, ds2, ... with other namespaces
                local t = {' xmlns:ds="urn:decoy"'}
                for i = 1, n - 1 do
                    t[#t + 1] = string.format(' xmlns:ds%d="urn:decoy"', i)
                end
                return table.concat(t)
            end
            local function try(name, body)
                ngx.update_time()
                local started = ngx.now()
                local signed, code, detail = signer.sign(body, conf, 1790856000)
                ngx.update_time()
                assert(ngx.now() - started < 2, name .. " took too long")
                ngx.say(name, ": ", signed and "signed" or (code .. " " .. detail))
            end

            local attributes = {}
            for i = 1, 257 do
                attributes[i] = string.format(' a%d="v"', i)
            end
            try("256 attributes", envelope("", "<p" .. table.concat(attributes, "", 1, 256) .. "/>"))
            try("257 attributes", envelope("", "<p" .. table.concat(attributes) .. "/>"))
            -- the Envelope declares the SOAP namespace, so 127 decoys reach the limit
            try("128 namespaces in scope", envelope(decoy_prefixes(127)))
            try("129 namespaces in scope", envelope(decoy_prefixes(128)))
            -- prefix collisions used to make namespace lookup quadratic
            try("16000 colliding prefixes", envelope(decoy_prefixes(16000)))
            try("5 MB of attributes on one element",
                envelope("", "<p" .. string.rep(' a="v"', 870000) .. "/>"))
        }
    }
--- request
GET /t
--- response_body
256 attributes: signed
257 attributes: invalid_soap an element has more than 256 attributes
128 namespaces in scope: signed
129 namespaces in scope: invalid_soap more than 128 namespace declarations are in scope
16000 colliding prefixes: invalid_soap an element has more than 256 attributes
5 MB of attributes on one element: invalid_soap an element has more than 256 attributes
--- timeout: 30



=== TEST 13: warn about a signing certificate outside its validity period
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            -- t/certs/etcd.pem is an RSA certificate that expired in 2021
            local signed = signer.sign(
                '<s:Envelope xmlns:s="' .. signer.namespaces.soap11 .. '"><s:Body/></s:Envelope>',
                {
                    credentials = {
                        certificate = read("t/certs/etcd.pem"),
                        private_key = read("t/certs/etcd.key"),
                    },
                    soap = {version = "auto", must_understand = true},
                    timestamp = {ttl_seconds = 300},
                })
            ngx.say(signed ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
the signing certificate expired at 2021-10-28T03:33:02Z; verifiers will reject the signatures



=== TEST 14: apply schema defaults when sign is called without optional sections
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local signed = assert(signer.sign(
                '<s:Envelope xmlns:s="' .. signer.namespaces.soap11 .. '"><s:Body/></s:Envelope>',
                {credentials = {
                    certificate = read("t/certs/server.crt"),
                    private_key = read("t/certs/server.key"),
                }},
                1790856000))
            local ns = signer.namespaces
            local doc = assert(xml.parse(signed))
            local security = assert(xml.find_all(xml.root(doc), ns.wsse, "Security")[1])
            local timestamp = assert(xml.find_child(security, ns.wsu, "Timestamp"))
            ngx.say("mustUnderstand=", xml.get_namespaced_property(security, ns.soap11,
                                                                  "mustUnderstand"))
            ngx.say("Created=", xml.content(xml.find_child(timestamp, ns.wsu, "Created")))
            ngx.say("Expires=", xml.content(xml.find_child(timestamp, ns.wsu, "Expires")))
            xml.free_document(doc)
        }
    }
--- request
GET /t
--- response_body
mustUnderstand=1
Created=2026-10-01T12:00:00Z
Expires=2026-10-01T12:05:00Z



=== TEST 15: reuse only an empty wsse:Security header by default
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local function conf(allow)
                return {
                    credentials = {
                        certificate = read("t/certs/server.crt"),
                        private_key = read("t/certs/server.key"),
                    },
                    soap = {version = "auto", must_understand = true,
                            allow_existing_security_content = allow},
                    timestamp = {ttl_seconds = 300},
                }
            end
            local function envelope(security)
                return string.format(
                    '<s:Envelope xmlns:s="%s" xmlns:wsse="%s"><s:Header>'
                    .. '<wsse:Security>%s</wsse:Security></s:Header>'
                    .. '<s:Body><Ping/></s:Body></s:Envelope>', ns.soap11, ns.wsse, security)
            end
            local token = "<wsse:UsernameToken><wsse:Username>admin</wsse:Username>"
                          .. "</wsse:UsernameToken>"

            for _, case in ipairs({
                {"token, default", token, nil},
                {"text, default", "unexpected", nil},
                {"token, allowed", token, true},
                {"empty, default", "", nil},
                {"whitespace and comment, default", "\n  <!-- client -->\n", nil},
            }) do
                local signed, code, detail = signer.sign(envelope(case[2]), conf(case[3]),
                                                         1790856000)
                if signed then
                    local doc = assert(xml.parse(signed))
                    local root = assert(xml.root(doc))
                    ngx.say(case[1], ": signed, ", #xml.find_all(root, ns.wsse, "Security"),
                            " Security header")
                    xml.free_document(doc)
                else
                    ngx.say(case[1], ": ", code, " ", detail)
                end
            end
        }
    }
--- request
GET /t
--- response_body
token, default: invalid_soap wsse:Security header already has content
text, default: invalid_soap wsse:Security header already has content
token, allowed: signed, 1 Security header
empty, default: signed, 1 Security header
whitespace and comment, default: signed, 1 Security header



=== TEST 16: sign Body namespace declarations used only in content with InclusiveNamespaces
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

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
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end
            -- returns the Body reference's PrefixList, and whether its digest
            -- matches a recomputation of the (possibly modified) message
            local function check(signed)
                local doc = assert(xml.parse(signed))
                local root = assert(xml.root(doc))
                local body = assert(xml.find_child(root, ns.soap11, "Body"))
                local body_id = xml.get_namespaced_property(body, ns.wsu, "Id")
                local prefix_list, matches
                for _, reference in ipairs(xml.find_all(root, ns.ds, "Reference")) do
                    if xml.get_property(reference, "URI") == "#" .. body_id then
                        local inclusive = xml.find_all(reference, exclusive,
                                                       "InclusiveNamespaces")[1]
                        prefix_list = inclusive and xml.get_property(inclusive, "PrefixList")
                        local prefixes = {}
                        for prefix in (prefix_list or ""):gmatch("%S+") do
                            prefixes[#prefixes + 1] = prefix
                        end
                        local expected = xml.content(
                            assert(xml.find_child(reference, ns.ds, "DigestValue")))
                        matches = sha256(assert(xml.canonicalize(body, prefixes))) == expected
                    end
                end
                xml.free_document(doc)
                return prefix_list, matches
            end

            -- "xsd" is only used inside an attribute value
            local signed = assert(signer.sign(
                '<s:Envelope xmlns:s="' .. ns.soap11 .. '"'
                .. ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
                .. ' xmlns:xsd="http://www.w3.org/2001/XMLSchema">'
                .. '<s:Body><Id xmlns="urn:e2e" xsi:type="xsd:string">42</Id></s:Body>'
                .. '</s:Envelope>', conf, 1790856000))
            local prefix_list, matches = check(signed)
            ngx.say("PrefixList=", prefix_list, " digest matches: ", matches)
            local rebound = signed:gsub('xmlns:xsd="http://www.w3.org/2001/XMLSchema"',
                                        'xmlns:xsd="urn:attacker"')
            local _, rebound_matches = check(rebound)
            ngx.say("rebound digest matches: ", rebound_matches)

            -- when every declaration is used, the output is unchanged
            signed = assert(signer.sign(
                '<s:Envelope xmlns:s="' .. ns.soap11 .. '"><s:Body><p:Ping xmlns:p="urn:p"/>'
                .. '</s:Body></s:Envelope>', conf, 1790856000))
            prefix_list, matches = check(signed)
            ngx.say("PrefixList=", tostring(prefix_list), " digest matches: ", matches)
        }
    }
--- request
GET /t
--- response_body
PrefixList=xsd digest matches: true
rebound digest matches: false
PrefixList=nil digest matches: true



=== TEST 17: keep the attribute pre-check linear for long text without "="
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local xml = require("apisix.plugins.soap-signer.xml")
            -- 32 MB of ~1.4 KB paragraphs without "=": every paragraph is a
            -- segment long enough to be checked, and searching past the
            -- segment made the check quadratic (about 15 s here)
            local paragraph = "<p>" .. string.rep("lorem ipsum ", 120) .. "</p>"
            local body = '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
                         .. "<s:Body>" .. string.rep(paragraph, 23000) .. "</s:Body></s:Envelope>"
            ngx.update_time()
            local started = ngx.now()
            local doc, err = xml.parse(body)
            ngx.update_time()
            local elapsed = ngx.now() - started
            assert(doc, err)
            xml.free_document(doc)
            assert(elapsed < 2, "parsing took " .. elapsed .. " s")
            ngx.say("parsed ", math.floor(#body / 1048576), " MB")
        }
    }
--- request
GET /t
--- response_body
parsed 31 MB
--- timeout: 60



=== TEST 18: accept only UTF-8 so that the limit checks see the parsed bytes
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces

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
            local function envelope(body, declaration)
                return (declaration or "") .. '<s:Envelope xmlns:s="' .. ns.soap11 .. '">'
                       .. "<s:Body>" .. body .. "</s:Body></s:Envelope>"
            end
            local function utf16le(value)
                return (value:gsub(".", "%0\0"))
            end
            local attributes = {}
            for i = 1, 300000 do
                attributes[i] = string.format(' a%d="v"', i)
            end
            local function try(name, body)
                ngx.update_time()
                local started = ngx.now()
                local signed, code, detail = signer.sign(body, conf, 1790856000)
                ngx.update_time()
                assert(ngx.now() - started < 2, name .. " took too long")
                if signed then
                    local doc = assert(xml.parse(signed))
                    local soap_body = assert(xml.find_child(xml.root(doc), ns.soap11, "Body"))
                    ngx.say(name, ": signed, text=",
                            xml.content(assert(xml.find_child(soap_body, "", "v"))))
                    xml.free_document(doc)
                else
                    ngx.say(name, ": ", code, " ", detail)
                end
            end

            try("UTF-16 with BOM", "\255\254" .. utf16le(envelope("<v>x</v>")))
            try("UTF-16 attribute attack",
                "\255\254" .. utf16le(envelope("<p" .. table.concat(attributes) .. "/>")))
            try("Latin-1 bytes", envelope("<v>caf\233</v>",
                                          '<?xml version="1.0" encoding="ISO-8859-1"?>'))
            -- the declaration is ignored, so "+ADw-" stays text instead of "<"
            try("UTF-7 declaration", envelope("<v>+ADw-x/+AD4-</v>",
                                              '<?xml version="1.0" encoding="UTF-7"?>'))
            try("UTF-8 with BOM", "\239\187\191" .. envelope("<v>caf\195\169</v>"))
        }
    }
--- request
GET /t
--- response_body
UTF-16 with BOM: invalid_soap only UTF-8 encoded XML is supported
UTF-16 attribute attack: invalid_soap only UTF-8 encoded XML is supported
Latin-1 bytes: invalid_soap failed to parse XML
UTF-7 declaration: signed, text=+ADw-x/+AD4-
UTF-8 with BOM: signed, text=café
--- timeout: 30



=== TEST 19: sign Body prefixes referenced in content, within a bounded PrefixList
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

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
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end
            -- the Body reference's PrefixList in `signed`, and whether its
            -- digest still matches the Body of `modified`
            local function check(signed, modified)
                local doc = assert(xml.parse(signed))
                local root = assert(xml.root(doc))
                local body = assert(xml.find_child(root, ns.soap11, "Body"))
                local reference_uri = "#" .. xml.get_namespaced_property(body, ns.wsu, "Id")
                local prefix_list, expected
                for _, reference in ipairs(xml.find_all(root, ns.ds, "Reference")) do
                    if xml.get_property(reference, "URI") == reference_uri then
                        local inclusive = xml.find_all(reference, exclusive,
                                                       "InclusiveNamespaces")[1]
                        prefix_list = inclusive and xml.get_property(inclusive, "PrefixList")
                        expected = xml.content(
                            assert(xml.find_child(reference, ns.ds, "DigestValue")))
                    end
                end
                xml.free_document(doc)

                doc = assert(xml.parse(modified or signed))
                body = assert(xml.find_child(assert(xml.root(doc)), ns.soap11, "Body"))
                local prefixes = {}
                for prefix in (prefix_list or ""):gmatch("%S+") do
                    prefixes[#prefixes + 1] = prefix
                end
                local matches = sha256(assert(xml.canonicalize(body, prefixes))) == expected
                xml.free_document(doc)
                return prefix_list, matches
            end
            local function envelope(declarations, body)
                return '<s:Envelope xmlns:s="' .. ns.soap11 .. '"' .. declarations .. ">"
                       .. "<s:Body>" .. body .. "</s:Body></s:Envelope>"
            end

            -- "o" is used by an element name and referenced in content
            local signed = assert(signer.sign(envelope(
                ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:o="urn:a"',
                '<o:Order><b><Item xsi:type="o:T">1</Item></b></o:Order>'), conf, 1790856000))
            local prefix_list, matches = check(signed)
            ngx.say("PrefixList=", prefix_list, " digest matches: ", matches)
            -- inserting a declaration that rebinds "o" for <Item> only
            local attacked = signed:gsub("<b>", '<b xmlns:o="urn:evil">')
            local _
            _, matches = check(signed, attacked)
            ngx.say("rebinding on an intermediate element detected: ", not matches)

            local function prefixes(n)
                local declarations, references = {}, {}
                for i = 1, n do
                    declarations[i] = string.format(' xmlns:p%d="urn:p%d"', i, i)
                    references[i] = string.format("<v>p%d:T</v>", i)
                end
                return envelope(table.concat(declarations), table.concat(references))
            end
            prefix_list = check(assert(signer.sign(prefixes(8), conf, 1790856000)))
            ngx.say("8 referenced prefixes: ", prefix_list)
            local _, code, detail = signer.sign(prefixes(9), conf, 1790856000)
            ngx.say("9 referenced prefixes: ", code, " ", detail)

            -- many unreferenced declarations no longer reach the PrefixList
            local declarations = {}
            for i = 1, 126 do
                declarations[i] = string.format(' xmlns:p%d="urn:p%d"', i, i)
            end
            local head = envelope(table.concat(declarations), "")
            ngx.update_time()
            local started = ngx.now()
            assert(signer.sign(envelope(table.concat(declarations),
                               string.rep("<a/>", math.floor((5242880 - #head) / 4) - 2)),
                               conf, 1790856000))
            ngx.update_time()
            local elapsed = ngx.now() - started
            assert(elapsed < 3, "signing took " .. elapsed .. " s")
            ngx.say("126 unreferenced declarations and 5 MB of elements: signed")
        }
    }
--- request
GET /t
--- response_body
PrefixList=o digest matches: true
rebinding on an intermediate element detected: true
8 referenced prefixes: p1 p2 p3 p4 p5 p6 p7 p8
9 referenced prefixes: invalid_soap more than 8 namespace prefixes are referenced in content
126 unreferenced declarations and 5 MB of elements: signed
--- timeout: 30



=== TEST 20: keep the InclusiveNamespaces prefix from colliding with the message
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            -- the message binds "ec" to XML-DSig, so the signature reuses "ec"
            -- for its own elements, and the Body refers to a declared prefix
            local signed = assert(signer.sign(
                '<s:Envelope xmlns:s="' .. ns.soap11 .. '" xmlns:ec="' .. ns.ds .. '"'
                .. ' xmlns:o="urn:a"><s:Body><v>o:T</v></s:Body></s:Envelope>',
                {
                    credentials = {
                        certificate = certificate_pem,
                        private_key = read("t/certs/server.key"),
                    },
                    soap = {version = "auto", must_understand = true},
                    timestamp = {ttl_seconds = 300},
                }, 1790856000))
            local doc = assert(xml.parse(signed))
            local signature = assert(xml.find_all(xml.root(doc), ns.ds, "Signature")[1])
            ngx.say("Transform elements in the XML-DSig namespace: ",
                    #xml.find_all(signature, ns.ds, "Transform"))
            ngx.say("InclusiveNamespaces in the exc-c14n namespace: ",
                    #xml.find_all(signature, exclusive, "InclusiveNamespaces"))
            local signed_info = assert(xml.find_child(signature, ns.ds, "SignedInfo"))
            local value = assert(xml.find_child(signature, ns.ds, "SignatureValue"))
            local public_key = assert(assert(x509.new(certificate_pem, "PEM")):get_pubkey())
            ngx.say("signature verified: ", (public_key:verify(
                assert(ngx.decode_base64(xml.content(value))),
                assert(xml.canonicalize(signed_info)), "sha256")))
            xml.free_document(doc)
        }
    }
--- request
GET /t
--- response_body
Transform elements in the XML-DSig namespace: 2
InclusiveNamespaces in the exc-c14n namespace: 1
signature verified: true



=== TEST 21: review regressions: rebinding a prefix on the element that refers to it, and UTF-16 namespace declarations
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.soap-signer.signer")
            local xml = require("apisix.plugins.soap-signer.xml")
            local ns = signer.namespaces
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

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
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end

            -- "p" is declared on the Body, used by <p:Marker/>, and referred
            -- to by a sibling's xsi:type
            local signed = assert(signer.sign(
                '<s:Envelope xmlns:s="' .. ns.soap11 .. '"'
                .. ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
                .. '<s:Body xmlns:p="urn:a"><Item xsi:type="p:Type"/><p:Marker/></s:Body>'
                .. '</s:Envelope>', conf, 1790856000))
            local function body_reference(doc)
                local root = assert(xml.root(doc))
                local body = assert(xml.find_child(root, ns.soap11, "Body"))
                local uri = "#" .. xml.get_namespaced_property(body, ns.wsu, "Id")
                for _, reference in ipairs(xml.find_all(root, ns.ds, "Reference")) do
                    if xml.get_property(reference, "URI") == uri then
                        return body, reference
                    end
                end
            end
            local doc = assert(xml.parse(signed))
            local _, reference = body_reference(doc)
            local inclusive = assert(xml.find_all(reference, exclusive, "InclusiveNamespaces")[1])
            local prefix_list = xml.get_property(inclusive, "PrefixList")
            local expected = xml.content(assert(xml.find_child(reference, ns.ds, "DigestValue")))
            xml.free_document(doc)
            ngx.say("PrefixList=", prefix_list)

            -- rebind "p" on <Item> only, which changes the meaning of its type
            local tampered = signed:gsub("<Item ", '<Item xmlns:p="urn:other" ')
            doc = assert(xml.parse(tampered))
            local body = body_reference(doc)
            local matches = sha256(assert(xml.canonicalize(body, {prefix_list}))) == expected
            xml.free_document(doc)
            ngx.say("rebinding on the referring element detected: ", not matches)

            -- UTF-16 hides namespace declarations from the byte-based check
            local open, close = {}, {}
            for level = 1, 16 do
                local declarations = {}
                for i = 1, 64 do
                    declarations[i] = string.format(' xmlns:n%d_%d="u"', level, i)
                end
                open[level] = "<e" .. table.concat(declarations) .. ">"
                close[level] = "</e>"
            end
            local message = '<s:Envelope xmlns:s="' .. ns.soap11 .. '"><s:Body>'
                            .. table.concat(open) .. string.rep("<a/>", 20000)
                            .. table.concat(close) .. "</s:Body></s:Envelope>"
            ngx.update_time()
            local started = ngx.now()
            local _, code, detail = signer.sign("\255\254" .. message:gsub(".", "%0\0"),
                                                conf, 1790856000)
            ngx.update_time()
            assert(ngx.now() - started < 2)
            ngx.say("UTF-16 with 1024 namespaces in scope: ", code, " ", detail)
        }
    }
--- request
GET /t
--- response_body
PrefixList=p
rebinding on the referring element detected: true
UTF-16 with 1024 namespaces in scope: invalid_soap only UTF-8 encoded XML is supported
--- timeout: 30
