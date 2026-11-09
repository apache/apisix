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
            local plugin = require("apisix.plugins.xml-signer")
            local ok = plugin.check_schema({
                credentials = {
                    certificate = "$secret://vault/signing/certificate",
                    private_key = "$secret://vault/signing/private-key",
                },
            })
            ngx.say(ok)

            ok = plugin.check_schema({
                credentials = {certificate = "certificate"},
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



=== TEST 2: sign and verify enveloped XMLDSig
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local signed = assert(signer.sign(
                '<?xml version="1.0" encoding="ISO-8859-1"?>'
                .. '<?before-signing preserve?>'
                .. '<root xmlns="urn:test"><value>42 \195\169</value></root>'
                .. '<?after-signing preserve?>',
                {credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                }},
                "UTF-8"
            ))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local value = assert(xml.find_child(root, "urn:test", "value"))
            assert(xml.content(value) == "42 \195\169")
            local signature = assert(xml.find_all(
                root, signer.namespaces.ds, "Signature")[1])
            local signed_info = assert(xml.find_child(
                signature, signer.namespaces.ds, "SignedInfo"))
            local signature_value = assert(xml.find_child(
                signature, signer.namespaces.ds, "SignatureValue"))
            local reference = assert(xml.find_child(
                signed_info, signer.namespaces.ds, "Reference"))
            local digest_value = assert(xml.find_child(
                reference, signer.namespaces.ds, "DigestValue"))

            local canonical_signed_info = assert(xml.canonicalize(signed_info))
            local raw_signature = assert(ngx.decode_base64(xml.content(signature_value)))
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            assert(public_key:verify(raw_signature, canonical_signed_info, "sha256"))

            local expected_digest = xml.content(digest_value)
            xml.remove(signature)
            local canonical_document = assert(xml.canonicalize_document(doc))
            local context = assert(digest.new("sha256"))
            assert(context:update(canonical_document))
            assert(ngx.encode_base64(assert(context:final())) == expected_digest)
            xml.free_document(doc)
            ngx.say("verified")
        }
    }
--- request
GET /t
--- response_body
verified



=== TEST 3: reject unsafe and already signed XML
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")
            local credentials = {
                certificate = "unused",
                private_key = "unused",
            }
            local _, code = signer.sign(
                '<!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>'
                .. '<root>&xxe;</root>',
                {credentials = credentials}
            )
            ngx.say(code)

            _, code = signer.sign(
                '<root xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
                .. '<ds:Signature/></root>',
                {credentials = credentials}
            )
            ngx.say(code)
        }
    }
--- request
GET /t
--- response_body
invalid_xml
already_signed



=== TEST 4: reject non-RSA credentials
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local credentials = require("apisix.plugins.xml-signer.credentials")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local runtime, err = credentials.load({
                certificate = read("t/certs/apisix_ecc.crt"),
                private_key = read("t/certs/apisix_ecc.key"),
            })
            ngx.say(runtime == nil)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
true
private key must be RSA



=== TEST 5: sign and verify XMLDSig with RSA-SHA1
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local signed = assert(signer.sign(
                '<root xmlns="urn:test"><legacy>true</legacy></root>',
                {
                    credentials = {
                        certificate = certificate_pem,
                        private_key = read("t/certs/server.key"),
                    },
                    signature = {algorithm = "rsa-sha1"},
                }
            ))

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

            local reference = assert(xml.find_child(
                signed_info, signer.namespaces.ds, "Reference"))
            local digest_method = assert(xml.find_child(
                reference, signer.namespaces.ds, "DigestMethod"))
            assert(xml.get_property(digest_method, "Algorithm")
                   == signer.namespaces.ds .. "sha1")
            local digest_value = assert(xml.find_child(
                reference, signer.namespaces.ds, "DigestValue"))

            local signature_value = assert(xml.find_child(
                signature, signer.namespaces.ds, "SignatureValue"))
            local canonical_signed_info = assert(xml.canonicalize(signed_info))
            local raw_signature = assert(ngx.decode_base64(xml.content(signature_value)))
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            assert(public_key:verify(raw_signature, canonical_signed_info, "sha1"))

            local expected_digest = xml.content(digest_value)
            xml.remove(signature)
            local canonical_document = assert(xml.canonicalize(root))
            local context = assert(digest.new("sha1"))
            assert(context:update(canonical_document))
            assert(ngx.encode_base64(assert(context:final())) == expected_digest)
            xml.free_document(doc)
            ngx.say("verified rsa-sha1")
        }
    }
--- request
GET /t
--- response_body
verified rsa-sha1



=== TEST 6: sign XML without KeyInfo
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local signed = assert(signer.sign(
                '<root xmlns="urn:test"><value>42</value></root>',
                {
                    credentials = {
                        certificate = read("t/certs/server.crt"),
                        private_key = read("t/certs/server.key"),
                    },
                    signature = {
                        algorithm = "rsa-sha256",
                        key_info = "none",
                    },
                }
            ))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            assert(#xml.find_all(root, signer.namespaces.ds, "Signature") == 1)
            assert(#xml.find_all(root, signer.namespaces.ds, "KeyInfo") == 0)
            xml.free_document(doc)
            ngx.say("signed without KeyInfo")
        }
    }
--- request
GET /t
--- response_body
signed without KeyInfo



=== TEST 7: verify namespace conflicts and processing instructions without signer C14N
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")
            local ds = signer.namespaces.ds
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"
            local signature_uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
            local digest_uri = "http://www.w3.org/2001/04/xmlenc#sha256"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local signed = assert(signer.sign(
                '<?before preserve?><root xmlns="urn:test" xmlns:ds="urn:occupied">'
                .. '<!--not signed--><ds:item>1</ds:item>'
                .. '<plain xmlns="">note</plain></root><?after preserve?>',
                {credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                }}
            ))
            local expected_document = '<?before preserve?>\n<root xmlns="urn:test">'
                .. '<ds:item xmlns:ds="urn:occupied">1</ds:item>'
                .. '<plain xmlns="">note</plain></root>\n<?after preserve?>'
            local context = assert(digest.new("sha256"))
            assert(context:update(expected_document))
            local expected_digest = ngx.encode_base64(assert(context:final()))

            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local signature = assert(xml.find_all(root, ds, "Signature")[1])
            local actual_digest = assert(xml.find_all(signature, ds, "DigestValue")[1])
            assert(xml.content(actual_digest) == expected_digest)
            local expected_info = '<ds1:SignedInfo xmlns:ds1="' .. ds .. '">'
                .. '<ds1:CanonicalizationMethod Algorithm="' .. exclusive
                .. '"></ds1:CanonicalizationMethod>'
                .. '<ds1:SignatureMethod Algorithm="' .. signature_uri
                .. '"></ds1:SignatureMethod><ds1:Reference URI=""><ds1:Transforms>'
                .. '<ds1:Transform Algorithm="' .. ds .. 'enveloped-signature">'
                .. '</ds1:Transform><ds1:Transform Algorithm="' .. exclusive
                .. '"></ds1:Transform></ds1:Transforms>'
                .. '<ds1:DigestMethod Algorithm="' .. digest_uri
                .. '"></ds1:DigestMethod><ds1:DigestValue>' .. expected_digest
                .. '</ds1:DigestValue></ds1:Reference></ds1:SignedInfo>'
            local value = assert(xml.find_child(signature, ds, "SignatureValue"))
            local certificate = assert(x509.new(certificate_pem, "PEM"))
            local public_key = assert(certificate:get_pubkey())
            assert(public_key:verify(
                assert(ngx.decode_base64(xml.content(value))), expected_info, "sha256"))
            xml.free_document(doc)
            ngx.say("independent canonical form verified")
        }
    }
--- request
GET /t
--- response_body
independent canonical form verified



=== TEST 8: enforce minimum RSA key size per signature algorithm
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local x509 = require("resty.openssl.x509")
            local credentials = require("apisix.plugins.xml-signer.credentials")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")

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
            local body = '<root xmlns="urn:test"><legacy>true</legacy></root>'

            -- the default minimum is 2048 bits
            local runtime, err = credentials.load(weak)
            ngx.say(runtime == nil, " ", err)

            -- rsa-sha256 rejects a 1024-bit key
            local signed, code, detail = signer.sign(body, {
                credentials = weak,
                signature = {algorithm = "rsa-sha256"},
            })
            ngx.say(signed == nil, " ", code, " ", detail)

            -- rsa-sha1 accepts a 1024-bit key for legacy interoperability
            signed = assert(signer.sign(body, {
                credentials = weak,
                signature = {algorithm = "rsa-sha1"},
            }))
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

            -- a 2048-bit key is still rejected when a larger minimum is required
            runtime, err = credentials.load({
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }, 4096)
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
true RSA private key must be at least 4096 bits



=== TEST 9: reject XML that is not namespace well-formed
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {credentials = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }}
            for _, body in ipairs({
                '<r><a:x/></r>',
                '<r a:b="1"/>',
                '<r xmlns:a="urn:u" xmlns:b="urn:u" a:x="1" b:x="2"/>',
                '<r xmlns:a="not a uri"><a:x/></r>',
            }) do
                local signed, code, detail = signer.sign(body, conf)
                ngx.say(signed == nil, " ", code, " ", detail)
            end
            ngx.say(signer.sign('<a:r xmlns:a="urn:u"><a:x a:y="1"/></a:r>', conf) ~= nil)
        }
    }
--- request
GET /t
--- response_body
true invalid_xml failed to parse XML
true invalid_xml failed to parse XML
true invalid_xml failed to parse XML
true invalid_xml failed to parse XML
true



=== TEST 10: reject documents that make libxml2 parsing super-linear
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {credentials = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }}
            local function attributes(n)
                local t = {}
                for i = 1, n do
                    t[i] = string.format(' a%d="v"', i)
                end
                return table.concat(t)
            end
            local function nested(levels)
                local open, close = {}, {}
                for i = 1, levels do
                    open[i] = string.format('<e xmlns:n%d="urn:n">', i)
                    close[i] = "</e>"
                end
                return '<r xmlns:p="urn:p">' .. table.concat(open) .. "<p:a/>"
                       .. table.concat(close) .. "</r>"
            end
            local function try(name, body)
                ngx.update_time()
                local started = ngx.now()
                local signed, code, detail = signer.sign(body, conf)
                ngx.update_time()
                assert(ngx.now() - started < 2, name .. " took too long")
                ngx.say(name, ": ", signed and "signed" or (code .. " " .. detail))
            end

            try("256 attributes", "<r" .. attributes(256) .. "/>")
            try("257 attributes", "<r" .. attributes(257) .. "/>")
            -- the root declares one namespace, each nested level one more
            try("128 namespaces in scope", nested(127))
            try("129 namespaces in scope", nested(128))
            -- declarations in comments, CDATA, processing instructions and
            -- attribute values are not namespace declarations
            local decoys = string.rep('<!-- xmlns:c="u" --><![CDATA[ xmlns:d="u" ]]>'
                                      .. '<?pi xmlns:e="u"?><x v=" xmlns:f=&quot;u&quot; >"/>',
                                      200)
            try("decoys are not counted", '<r xmlns:p="urn:p">' .. decoys .. "</r>")
            -- sibling elements that redeclare a namespace have one in scope
            try("2000 sibling declarations",
                "<r>" .. string.rep('<a xmlns="urn:x">1</a>', 2000) .. "</r>")
            try("DTD with many declarations",
                '<!DOCTYPE r [<!ENTITY a "b">]><r' .. string.rep(' xmlns:a="u"', 200) .. "/>")

            -- 5 MB attack documents are rejected before they reach libxml2
            local limit = 5242880
            try("5 MB of attributes on one element",
                "<r" .. attributes(math.floor((limit - 10) / 9)) .. "/>")
            local open, close = {}, {}
            for i = 1, 64 do
                local t = {"<e"}
                for j = 1, 64 do
                    t[#t + 1] = string.format(' xmlns:n%d_%d="u"', i, j)
                end
                open[i] = table.concat(t) .. ">"
                close[i] = "</e>"
            end
            local head = '<r xmlns:p="urn:p">' .. table.concat(open)
            local tail = table.concat(close) .. "</r>"
            try("5 MB with 4096 namespaces in scope",
                head .. string.rep("<p:a/>", math.floor((limit - #head - #tail) / 6)) .. tail)
        }
    }
--- request
GET /t
--- response_body
256 attributes: signed
257 attributes: invalid_xml an element has more than 256 attributes
128 namespaces in scope: signed
129 namespaces in scope: invalid_xml more than 128 namespace declarations are in scope
decoys are not counted: signed
2000 sibling declarations: signed
DTD with many declarations: invalid_xml DTD and entity declarations are not allowed
5 MB of attributes on one element: invalid_xml an element has more than 256 attributes
5 MB with 4096 namespaces in scope: invalid_xml more than 128 namespace declarations are in scope
--- timeout: 30



=== TEST 11: warn about a signing certificate outside its validity period
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            -- t/certs/etcd.pem is an RSA certificate that expired in 2021
            local signed = signer.sign("<r/>", {credentials = {
                certificate = read("t/certs/etcd.pem"),
                private_key = read("t/certs/etcd.key"),
            }})
            ngx.say(signed ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
the signing certificate expired at 2021-10-28T03:33:02Z; verifiers will reject the signatures



=== TEST 12: sign namespace declarations used only in content with InclusiveNamespaces
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")
            local ds = signer.namespaces.ds
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            local conf = {credentials = {
                certificate = certificate_pem,
                private_key = read("t/certs/server.key"),
            }}
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end
            local function inspect(signed)
                local doc = assert(xml.parse(signed))
                local signature = assert(xml.find_all(xml.root(doc), ds, "Signature")[1])
                local signed_info = assert(xml.find_child(signature, ds, "SignedInfo"))
                local inclusive = xml.find_all(signed_info, exclusive, "InclusiveNamespaces")[1]
                local prefix_list = inclusive and xml.get_property(inclusive, "PrefixList")
                local value = assert(xml.find_child(signature, ds, "SignatureValue"))
                local public_key = assert(assert(x509.new(certificate_pem, "PEM")):get_pubkey())
                local verified = public_key:verify(
                    assert(ngx.decode_base64(xml.content(value))),
                    assert(xml.canonicalize(signed_info)), "sha256")
                local expected = xml.content(assert(xml.find_all(signed_info, ds, "DigestValue")[1]))
                xml.free_document(doc)
                return prefix_list, verified, expected
            end
            local function document_digest(signed, prefixes)
                local doc = assert(xml.parse(signed))
                xml.remove(assert(xml.find_all(xml.root(doc), ds, "Signature")[1]))
                local value = sha256(assert(xml.canonicalize_document(doc, prefixes)))
                xml.free_document(doc)
                return value
            end

            -- "ns" is only used inside an attribute value
            local signed = assert(signer.sign(
                '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns="urn:orders:v1">'
                .. '<item xsi:type="ns:Order">42</item></r>', conf))
            local prefix_list, verified, expected = inspect(signed)
            ngx.say("PrefixList=", prefix_list, " signature=", verified)
            ngx.say("digest matches: ", document_digest(signed, {"ns"}) == expected)
            -- rebinding the prefix must invalidate the reference digest
            local rebound = signed:gsub("urn:orders:v1", "urn:attacker")
            ngx.say("rebound digest matches: ", document_digest(rebound, {"ns"}) == expected)

            -- when every declaration is used, the output is unchanged
            signed = assert(signer.sign('<p:r xmlns:p="urn:p"><p:x/></p:r>', conf))
            prefix_list, verified = inspect(signed)
            ngx.say("PrefixList=", tostring(prefix_list), " signature=", verified)
        }
    }
--- request
GET /t
--- response_body
PrefixList=ns signature=true
digest matches: true
rebound digest matches: false
PrefixList=nil signature=true



=== TEST 13: keep the attribute pre-check linear for long text without "="
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local xml = require("apisix.plugins.xml-signer.xml")
            -- 32 MB of ~1.4 KB paragraphs without "=": every paragraph is a
            -- segment long enough to be checked, and searching past the
            -- segment made the check quadratic (about 15 s here)
            local paragraph = "<p>" .. string.rep("lorem ipsum ", 120) .. "</p>"
            local body = "<r>" .. string.rep(paragraph, 23000) .. "</r>"
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



=== TEST 14: accept only UTF-8 so that the limit checks see the parsed bytes
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {credentials = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }}
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
                local signed, code, detail = signer.sign(body, conf)
                ngx.update_time()
                assert(ngx.now() - started < 2, name .. " took too long")
                if signed then
                    local doc = assert(xml.parse(signed))
                    ngx.say(name, ": signed, text=",
                            xml.content(assert(xml.find_child(xml.root(doc), "", "v"))))
                    xml.free_document(doc)
                else
                    ngx.say(name, ": ", code, " ", detail)
                end
            end

            try("UTF-16 with BOM", "\255\254" .. utf16le('<r a="1">x</r>'))
            try("UTF-16 attribute attack",
                "\255\254" .. utf16le("<r" .. table.concat(attributes) .. "/>"))
            try("EBCDIC", "\76\111\167\148\147\64\165\133\153\162\137\150\149")
            try("Latin-1 bytes", '<?xml version="1.0" encoding="ISO-8859-1"?><r>caf\233</r>')
            -- the declaration is ignored, so "+ADw-" stays text instead of "<"
            try("UTF-7 declaration",
                '<?xml version="1.0" encoding="UTF-7"?><r><v>+ADw-x/+AD4-</v></r>')
            try("UTF-8 with BOM", "\239\187\191<r><v>caf\195\169</v></r>")
        }
    }
--- request
GET /t
--- response_body
UTF-16 with BOM: invalid_xml only UTF-8 encoded XML is supported
UTF-16 attribute attack: invalid_xml only UTF-8 encoded XML is supported
EBCDIC: invalid_xml only UTF-8 encoded XML is supported
Latin-1 bytes: invalid_xml failed to parse XML
UTF-7 declaration: signed, text=+ADw-x/+AD4-
UTF-8 with BOM: signed, text=café
--- timeout: 30



=== TEST 15: sign prefixes referenced in content, within a bounded PrefixList
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")
            local ds = signer.namespaces.ds
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {credentials = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }}
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end
            -- PrefixList of the signed document, and whether the digest still
            -- matches `modified` (the signed document, possibly changed)
            local function check(signed, modified)
                local doc = assert(xml.parse(signed))
                local signature = assert(xml.find_all(xml.root(doc), ds, "Signature")[1])
                local inclusive = xml.find_all(signature, exclusive, "InclusiveNamespaces")[1]
                local prefix_list = inclusive and xml.get_property(inclusive, "PrefixList")
                local expected = xml.content(assert(xml.find_all(signature, ds, "DigestValue")[1]))
                xml.free_document(doc)

                doc = assert(xml.parse(modified or signed))
                xml.remove(assert(xml.find_all(xml.root(doc), ds, "Signature")[1]))
                local prefixes = {}
                for prefix in (prefix_list or ""):gmatch("%S+") do
                    prefixes[#prefixes + 1] = prefix
                end
                local matches = sha256(assert(xml.canonicalize_document(doc, prefixes))) == expected
                xml.free_document(doc)
                return prefix_list, matches
            end

            -- "ns" is used by an element name and referenced in content
            local signed = assert(signer.sign(
                '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns="urn:a">'
                .. '<ns:x/><b><item xsi:type="ns:T">1</item></b></r>', conf))
            local prefix_list, matches = check(signed)
            ngx.say("PrefixList=", prefix_list, " digest matches: ", matches)
            -- inserting a declaration that rebinds "ns" for <item> only
            local attacked = signed:gsub("<b>", '<b xmlns:ns="urn:evil">')
            _, matches = check(signed, attacked)
            ngx.say("rebinding on an intermediate element detected: ", not matches)

            -- declared prefixes that nothing refers to need no protection
            signed = assert(signer.sign('<r xmlns:u="urn:unused"><x/></r>', conf))
            ngx.say("unreferenced: PrefixList=", tostring((check(signed))))

            local function prefixes(n)
                local declarations, references = {}, {}
                for i = 1, n do
                    declarations[i] = string.format(' xmlns:p%d="urn:p%d"', i, i)
                    references[i] = string.format("<v>p%d:T</v>", i)
                end
                return "<r" .. table.concat(declarations) .. ">"
                       .. table.concat(references) .. "</r>"
            end
            prefix_list = check(assert(signer.sign(prefixes(8), conf)))
            ngx.say("8 referenced prefixes: ", prefix_list)
            local _, code, detail = signer.sign(prefixes(9), conf)
            ngx.say("9 referenced prefixes: ", code, " ", detail)

            -- many unreferenced declarations no longer reach the PrefixList,
            -- which made canonicalizing 5 MB take about a minute
            local declarations = {}
            for i = 1, 127 do
                declarations[i] = string.format(' xmlns:p%d="urn:p%d"', i, i)
            end
            local head = "<r" .. table.concat(declarations) .. ">"
            ngx.update_time()
            local started = ngx.now()
            assert(signer.sign(head .. string.rep("<a/>", math.floor((5242880 - #head) / 4) - 2)
                               .. "</r>", conf))
            ngx.update_time()
            local elapsed = ngx.now() - started
            assert(elapsed < 3, "signing took " .. elapsed .. " s")
            ngx.say("127 unreferenced declarations and 5 MB of elements: signed")
        }
    }
--- request
GET /t
--- response_body
PrefixList=ns digest matches: true
rebinding on an intermediate element detected: true
unreferenced: PrefixList=nil
8 referenced prefixes: p1 p2 p3 p4 p5 p6 p7 p8
9 referenced prefixes: invalid_xml more than 8 namespace prefixes are referenced in content
127 unreferenced declarations and 5 MB of elements: signed
--- timeout: 30



=== TEST 16: keep the InclusiveNamespaces prefix from colliding with the document
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local x509 = require("resty.openssl.x509")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")
            local ds = signer.namespaces.ds
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local certificate_pem = read("t/certs/server.crt")
            -- the document binds "ec" to XML-DSig, so the signature reuses "ec"
            -- for its own elements
            local signed = assert(signer.sign(
                '<r xmlns:ec="' .. ds .. '" xmlns:ns="urn:a"><item>ns:T</item></r>',
                {credentials = {
                    certificate = certificate_pem,
                    private_key = read("t/certs/server.key"),
                }}))
            local doc = assert(xml.parse(signed))
            local root = assert(xml.root(doc))
            local signature = assert(xml.find_all(root, ds, "Signature")[1])
            ngx.say("Transform elements in the XML-DSig namespace: ",
                    #xml.find_all(signature, ds, "Transform"))
            ngx.say("InclusiveNamespaces in the exc-c14n namespace: ",
                    #xml.find_all(signature, exclusive, "InclusiveNamespaces"))
            local signed_info = assert(xml.find_child(signature, ds, "SignedInfo"))
            local value = assert(xml.find_child(signature, ds, "SignatureValue"))
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



=== TEST 17: review regressions: rebinding a prefix on the element that refers to it, and UTF-16 namespace declarations
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            local digest = require("resty.openssl.digest")
            local signer = require("apisix.plugins.xml-signer.signer")
            local xml = require("apisix.plugins.xml-signer.xml")
            local ds = signer.namespaces.ds
            local exclusive = "http://www.w3.org/2001/10/xml-exc-c14n#"

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local conf = {credentials = {
                certificate = read("t/certs/server.crt"),
                private_key = read("t/certs/server.key"),
            }}
            local function sha256(value)
                local context = assert(digest.new("sha256"))
                assert(context:update(value))
                return ngx.encode_base64(assert(context:final()))
            end

            -- "p" is used by an element name (<p:marker/>) and by a sibling's
            -- xsi:type value
            local signed = assert(signer.sign(
                '<r xmlns:p="urn:a" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
                .. '<item xsi:type="p:T"/><p:marker/></r>', conf))
            local doc = assert(xml.parse(signed))
            local signature = assert(xml.find_all(xml.root(doc), ds, "Signature")[1])
            local inclusive = assert(xml.find_all(signature, exclusive, "InclusiveNamespaces")[1])
            local prefix_list = xml.get_property(inclusive, "PrefixList")
            local expected = xml.content(assert(xml.find_all(signature, ds, "DigestValue")[1]))
            xml.free_document(doc)
            ngx.say("PrefixList=", prefix_list)

            -- rebind "p" on <item> only, which changes the meaning of its type
            local tampered = signed:gsub("<item ", '<item xmlns:p="urn:b" ')
            doc = assert(xml.parse(tampered))
            xml.remove(assert(xml.find_all(xml.root(doc), ds, "Signature")[1]))
            local matches = sha256(assert(xml.canonicalize_document(doc, {prefix_list}))) == expected
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
            local body = "<r>" .. table.concat(open) .. string.rep("<a/>", 20000)
                         .. table.concat(close) .. "</r>"
            ngx.update_time()
            local started = ngx.now()
            local _, code, detail = signer.sign("\255\254" .. body:gsub(".", "%0\0"), conf)
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
UTF-16 with 1024 namespaces in scope: invalid_xml only UTF-8 encoded XML is supported
--- timeout: 30
