--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local algorithms = require("apisix.plugins.signing.algorithms")
local credentials = require("apisix.plugins.signing.credentials")
local xml = require("apisix.plugins.signing.xml")

local encode_base64 = ngx.encode_base64

local DS = "http://www.w3.org/2000/09/xmldsig#"
local ENVELOPED_SIGNATURE = DS .. "enveloped-signature"
local EXCLUSIVE_C14N = "http://www.w3.org/2001/10/xml-exc-c14n#"

local _M = {
    namespaces = {ds = DS},
}


local function build_signature(doc, root, runtime, algorithm, key_info_mode,
                               digest_value)
    local ds_ns = xml.ensure_namespace(doc, root, "ds", DS)
    local signature = xml.new_child(root, ds_ns, "Signature")
    local signed_info = xml.new_child(signature, ds_ns, "SignedInfo")

    local canonicalization_method = xml.new_child(
        signed_info, ds_ns, "CanonicalizationMethod")
    xml.set_property(canonicalization_method, "Algorithm", EXCLUSIVE_C14N)

    local signature_method = xml.new_child(signed_info, ds_ns, "SignatureMethod")
    xml.set_property(signature_method, "Algorithm", algorithm.signature_uri)

    local reference = xml.new_child(signed_info, ds_ns, "Reference")
    xml.set_property(reference, "URI", "")
    local transforms = xml.new_child(reference, ds_ns, "Transforms")
    local enveloped = xml.new_child(transforms, ds_ns, "Transform")
    xml.set_property(enveloped, "Algorithm", ENVELOPED_SIGNATURE)
    local canonicalization = xml.new_child(transforms, ds_ns, "Transform")
    xml.set_property(canonicalization, "Algorithm", EXCLUSIVE_C14N)

    local digest_method = xml.new_child(reference, ds_ns, "DigestMethod")
    xml.set_property(digest_method, "Algorithm", algorithm.digest_uri)
    xml.new_child(reference, ds_ns, "DigestValue", encode_base64(digest_value))

    local canonical, canonical_err = xml.canonicalize(signed_info)
    if not canonical then
        return nil, canonical_err
    end

    local signature_value, signature_err = runtime.private_key:sign(
        canonical, algorithm.digest)
    if not signature_value then
        return nil, signature_err
    end
    xml.new_child(signature, ds_ns, "SignatureValue", encode_base64(signature_value))

    if key_info_mode == "x509_data" then
        local key_info = xml.new_child(signature, ds_ns, "KeyInfo")
        local x509_data = xml.new_child(key_info, ds_ns, "X509Data")
        xml.new_child(x509_data, ds_ns, "X509Certificate",
                      encode_base64(runtime.certificate_der))
    end
    return signature
end


function _M.sign(body, conf)
    local algorithm_name = conf.signature and conf.signature.algorithm or "rsa-sha256"
    local algorithm = algorithms.get(algorithm_name)
    if not algorithm then
        return nil, "signing_error", "unsupported signature algorithm"
    end
    local key_info_mode = conf.signature and conf.signature.key_info or "x509_data"
    if key_info_mode ~= "x509_data" and key_info_mode ~= "none" then
        return nil, "signing_error", "unsupported KeyInfo mode"
    end

    local doc, parse_err = xml.parse(body)
    if not doc then
        return nil, "invalid_xml", parse_err
    end

    local root = xml.root(doc)
    if not root then
        xml.free_document(doc)
        return nil, "invalid_xml", "XML document has no root element"
    end

    if #xml.find_all(root, DS, "Signature") > 0 then
        xml.free_document(doc)
        return nil, "already_signed", "XML document already contains a signature"
    end

    local runtime, credential_err = credentials.load(conf.credentials)
    if not runtime then
        xml.free_document(doc)
        return nil, "credential_error", credential_err
    end

    xml.ensure_namespace(doc, root, "ds", DS)
    local canonical, canonical_err = xml.canonicalize_document(doc)
    if not canonical then
        xml.free_document(doc)
        return nil, "signing_error", canonical_err
    end

    local digest_value, digest_err = algorithms.hash(canonical, algorithm)
    if not digest_value then
        xml.free_document(doc)
        return nil, "signing_error", digest_err
    end

    local signature, signature_err = build_signature(
        doc, root, runtime, algorithm, key_info_mode, digest_value)
    if not signature then
        xml.free_document(doc)
        return nil, "signing_error", signature_err
    end

    local result, serialize_err = xml.serialize(doc)
    xml.free_document(doc)
    if not result then
        return nil, "signing_error", serialize_err
    end
    return result
end


return _M