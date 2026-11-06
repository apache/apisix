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
local random = require("resty.random")
local resty_string = require("resty.string")

local algorithms = require("apisix.plugins.signing.algorithms")
local credentials = require("apisix.plugins.signing.credentials")
local xml = require("apisix.plugins.signing.xml")

local ipairs = ipairs
local ngx = ngx
local os = os
local encode_base64 = ngx.encode_base64

local SOAP11 = "http://schemas.xmlsoap.org/soap/envelope/"
local SOAP12 = "http://www.w3.org/2003/05/soap-envelope"
local SOAP12_ULTIMATE_RECEIVER = SOAP12 .. "/role/ultimateReceiver"
local WSSE = "http://docs.oasis-open.org/wss/2004/01/"
             .. "oasis-200401-wss-wssecurity-secext-1.0.xsd"
local WSU = "http://docs.oasis-open.org/wss/2004/01/"
            .. "oasis-200401-wss-wssecurity-utility-1.0.xsd"
local DS = "http://www.w3.org/2000/09/xmldsig#"
local EXCLUSIVE_C14N = "http://www.w3.org/2001/10/xml-exc-c14n#"
local BASE64_ENCODING = "http://docs.oasis-open.org/wss/2004/01/"
                        .. "oasis-200401-wss-soap-message-security-1.0#Base64Binary"
local X509_V3 = "http://docs.oasis-open.org/wss/2004/01/"
                .. "oasis-200401-wss-x509-token-profile-1.0#X509v3"

local _M = {
    namespaces = {
        soap11 = SOAP11,
        soap12 = SOAP12,
        wsse = WSSE,
        wsu = WSU,
        ds = DS,
    },
}


local function new_id(prefix)
    local value, err = random.bytes(16, true)
    if not value then
        return nil, err
    end
    return prefix .. "-" .. resty_string.to_hex(value)
end


local function find_envelope_parts(doc)
    local root = xml.root(doc)
    if not root or xml.name(root) ~= "Envelope" then
        return nil, "not_soap", "root element is not SOAP Envelope"
    end

    local soap_namespace = xml.namespace_uri(root)
    if soap_namespace ~= SOAP11 and soap_namespace ~= SOAP12 then
        return nil, "not_soap", "unsupported SOAP namespace"
    end

    local body, header
    for child in xml.each_child(root) do
        if xml.namespace_uri(child) == soap_namespace then
            local name = xml.name(child)
            if name == "Body" then
                if body then
                    return nil, "invalid_soap", "exactly one SOAP Body is required"
                end
                body = child
            elseif name == "Header" then
                if header then
                    return nil, "invalid_soap", "at most one SOAP Header is allowed"
                end
                if body then
                    return nil, "invalid_soap", "SOAP Header must precede SOAP Body"
                end
                header = child
            end
        end
    end
    if not body then
        return nil, "invalid_soap", "SOAP Body is required"
    end

    if not header then
        header = xml.new_node(root.ns, "Header")
        xml.add_before(body, header)
    end

    return {
        doc = doc,
        root = root,
        header = header,
        body = body,
        soap_namespace = soap_namespace,
    }
end


local function find_security(header, soap_namespace)
    local role_attribute = soap_namespace == SOAP11 and "actor" or "role"
    local security
    for child in xml.each_child(header) do
        if xml.name(child) == "Security" and xml.namespace_uri(child) == WSSE then
            local role = xml.get_namespaced_property(child, soap_namespace, role_attribute)
            if role == nil or (soap_namespace == SOAP12
                               and role == SOAP12_ULTIMATE_RECEIVER) then
                if security then
                    return nil, "multiple wsse:Security headers target the ultimate receiver"
                end
                security = child
            end
        end
    end
    return security
end


local function ensure_namespaces(envelope)
    envelope.soap_ns = xml.ensure_namespace(
        envelope.doc, envelope.root, "soapenv", envelope.soap_namespace)
    envelope.wsse_ns = xml.ensure_namespace(envelope.doc, envelope.root, "wsse", WSSE)
    envelope.wsu_ns = xml.ensure_namespace(envelope.doc, envelope.root, "wsu", WSU)
    envelope.ds_ns = xml.ensure_namespace(envelope.doc, envelope.root, "ds", DS)
end


local function get_id(node)
    return xml.get_namespaced_property(node, WSU, "Id")
end


local function ensure_id(node, namespace, prefix)
    local existing = get_id(node)
    if existing and existing ~= "" then
        return existing
    end

    local id, err = new_id(prefix)
    if not id then
        return nil, err
    end
    xml.set_namespaced_property(node, namespace, "Id", id)
    return id
end


local function reject_duplicate_ids(root)
    local seen = {}
    local duplicate
    xml.walk(root, function(node)
        for _, id in ipairs(xml.id_values(node)) do
            if seen[id] then
                duplicate = id
            end
            seen[id] = true
        end
    end)
    if duplicate then
        return nil, "duplicate XML ID"
    end
    return true
end


local function timestamp_value(timestamp)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
end


local function build_timestamp(envelope, ttl_seconds, now)
    local timestamp = xml.new_child(envelope.security, envelope.wsu_ns, "Timestamp")
    local id, err = ensure_id(timestamp, envelope.wsu_ns, "TS")
    if not id then
        return nil, err
    end
    xml.new_child(timestamp, envelope.wsu_ns, "Created", timestamp_value(now))
    xml.new_child(timestamp, envelope.wsu_ns, "Expires",
                  timestamp_value(now + ttl_seconds))
    return timestamp
end


local function build_token(envelope, runtime, key_info_mode)
    if key_info_mode == "none" then
        return
    end

    local token_id, err = new_id("X509")
    if not token_id then
        return nil, err
    end

    local token = xml.new_child(envelope.security, envelope.wsse_ns,
                                "BinarySecurityToken",
                                encode_base64(runtime.certificate_der))
    xml.set_namespaced_property(token, envelope.wsu_ns, "Id", token_id)
    xml.set_property(token, "EncodingType", BASE64_ENCODING)
    xml.set_property(token, "ValueType", X509_V3)
    return token_id
end


local function add_reference(envelope, signed_info, target, algorithm)
    local canonical, canonical_err = xml.canonicalize(target)
    if not canonical then
        return nil, canonical_err
    end
    local digest_value, digest_err = algorithms.hash(canonical, algorithm)
    if not digest_value then
        return nil, digest_err
    end

    local reference = xml.new_child(signed_info, envelope.ds_ns, "Reference")
    xml.set_property(reference, "URI", "#" .. get_id(target))
    local transforms = xml.new_child(reference, envelope.ds_ns, "Transforms")
    local transform = xml.new_child(transforms, envelope.ds_ns, "Transform")
    xml.set_property(transform, "Algorithm", EXCLUSIVE_C14N)
    local digest_method = xml.new_child(reference, envelope.ds_ns, "DigestMethod")
    xml.set_property(digest_method, "Algorithm", algorithm.digest_uri)
    xml.new_child(reference, envelope.ds_ns, "DigestValue", encode_base64(digest_value))
    return true
end


local function build_signature(envelope, runtime, token_id, targets, algorithm,
                               key_info_mode)
    local signature = xml.new_child(envelope.security, envelope.ds_ns, "Signature")
    local signed_info = xml.new_child(signature, envelope.ds_ns, "SignedInfo")

    local canonicalization_method = xml.new_child(
        signed_info, envelope.ds_ns, "CanonicalizationMethod")
    xml.set_property(canonicalization_method, "Algorithm", EXCLUSIVE_C14N)
    local signature_method = xml.new_child(signed_info, envelope.ds_ns, "SignatureMethod")
    xml.set_property(signature_method, "Algorithm", algorithm.signature_uri)

    for _, target in ipairs(targets) do
        local ok, err = add_reference(envelope, signed_info, target, algorithm)
        if not ok then
            return nil, err
        end
    end

    local canonical, canonical_err = xml.canonicalize(signed_info)
    if not canonical then
        return nil, canonical_err
    end
    local signature_value, signature_err = runtime.private_key:sign(
        canonical, algorithm.digest)
    if not signature_value then
        return nil, signature_err
    end
    xml.new_child(signature, envelope.ds_ns, "SignatureValue",
                  encode_base64(signature_value))

    if key_info_mode == "binary_security_token" then
        local key_info = xml.new_child(signature, envelope.ds_ns, "KeyInfo")
        local token_reference = xml.new_child(key_info, envelope.wsse_ns,
                                              "SecurityTokenReference")
        local reference = xml.new_child(token_reference, envelope.wsse_ns, "Reference")
        xml.set_property(reference, "URI", "#" .. token_id)
        xml.set_property(reference, "ValueType", X509_V3)
    end
    return signature
end


local function set_must_understand(envelope, enabled)
    local value = enabled and "1" or "0"
    if envelope.soap_namespace == SOAP12 then
        value = enabled and "true" or "false"
    end
    xml.set_namespaced_property(envelope.security, envelope.soap_ns,
                                "mustUnderstand", value)
end


function _M.sign(body, conf, now)
    local algorithm_name = conf.signature and conf.signature.algorithm or "rsa-sha256"
    local algorithm = algorithms.get(algorithm_name)
    if not algorithm then
        return nil, "signing_error", "unsupported signature algorithm"
    end
    local key_info_mode = conf.signature
                          and conf.signature.key_info or "binary_security_token"
    if key_info_mode ~= "binary_security_token" and key_info_mode ~= "none" then
        return nil, "signing_error", "unsupported KeyInfo mode"
    end

    local doc, parse_err = xml.parse(body)
    if not doc then
        return nil, "invalid_soap", parse_err
    end

    local envelope, code, envelope_err = find_envelope_parts(doc)
    if not envelope then
        xml.free_document(doc)
        return nil, code, envelope_err
    end

    local actual_version = envelope.soap_namespace == SOAP12 and "1.2" or "1.1"
    if conf.soap.version ~= "auto" and conf.soap.version ~= actual_version then
        xml.free_document(doc)
        return nil, "not_soap", "SOAP version does not match configuration"
    end
    if #xml.find_all(envelope.root, DS, "Signature") > 0 then
        xml.free_document(doc)
        return nil, "already_signed", "SOAP message already contains a signature"
    end

    local unique, unique_err = reject_duplicate_ids(envelope.root)
    if not unique then
        xml.free_document(doc)
        return nil, "invalid_soap", unique_err
    end

    local security_err
    envelope.security, security_err = find_security(envelope.header,
                                                     envelope.soap_namespace)
    if security_err then
        xml.free_document(doc)
        return nil, "invalid_soap", security_err
    end
    if envelope.security and xml.find_child(envelope.security, WSU, "Timestamp") then
        xml.free_document(doc)
        return nil, "invalid_soap", "wsse:Security already contains a wsu:Timestamp"
    end

    local runtime, credential_err = credentials.load(conf.credentials)
    if not runtime then
        xml.free_document(doc)
        return nil, "credential_error", credential_err
    end

    ensure_namespaces(envelope)
    if not envelope.security then
        envelope.security = xml.new_child(envelope.header, envelope.wsse_ns, "Security")
    end
    set_must_understand(envelope, conf.soap.must_understand)

    local body_id, body_id_err = ensure_id(envelope.body, envelope.wsu_ns, "Body")
    if not body_id then
        xml.free_document(doc)
        return nil, "signing_error", body_id_err
    end
    local timestamp, timestamp_err = build_timestamp(
        envelope, conf.timestamp.ttl_seconds, now or ngx.time())
    if not timestamp then
        xml.free_document(doc)
        return nil, "signing_error", timestamp_err
    end
    local token_id, token_err = build_token(envelope, runtime, key_info_mode)
    if key_info_mode == "binary_security_token" and not token_id then
        xml.free_document(doc)
        return nil, "signing_error", token_err
    end

    local signature, signature_err = build_signature(
        envelope, runtime, token_id, {envelope.body, timestamp}, algorithm,
        key_info_mode)
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