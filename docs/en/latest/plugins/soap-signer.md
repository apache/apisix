---
title: soap-signer
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - SOAP
  - WS-Security
description: The soap-signer Plugin signs SOAP request bodies with an X.509 WS-Security signature.
---

<!--
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
-->

## Description

The `soap-signer` Plugin signs SOAP 1.1 and SOAP 1.2 request bodies using
WS-Security. It adds a `wsse:Security` header containing a Timestamp, an X.509
BinarySecurityToken, and an XML Signature over the SOAP Body and Timestamp.

The Plugin supports RSA-SHA256 for normal use and RSA-SHA1 for interoperability
with legacy SOAP services. It uses exclusive XML canonicalization without
comments. By default, it references an embedded certificate through a
WS-Security `SecurityTokenReference`; KeyInfo and the token can be omitted when
the verifier obtains the certificate out of band.

Use exactly one of `soap-signer` and `xml-signer` for a request. SOAP is XML,
and both plugins can accept `application/xml`; enabling both causes the second
plugin to reject the already-signed message.

## How it works

For a matching request, the Plugin performs the following operations during the
rewrite phase:

1. Buffers and parses the SOAP XML with external network access disabled.
2. Detects SOAP 1.1 or SOAP 1.2 from the Envelope namespace and validates it
   against `soap.version`.
3. Preserves an existing SOAP Header, which must precede the Body, or creates
   one before the Body.
4. Creates or reuses `wsse:Security` and sets the SOAP `mustUnderstand`
   attribute. A reused header must not already contain a `wsu:Timestamp`.
5. Assigns a `wsu:Id` to the Body when it does not already have one.
6. Creates a UTC Timestamp with `Created`, `Expires`, and a unique `wsu:Id`.
7. Embeds the X.509 certificate in a `wsse:BinarySecurityToken` unless
  `signature.key_info` is `none`.
8. Calculates a digest for both the Body and Timestamp using the algorithm
   selected by `signature.algorithm`.
9. Signs canonicalized `ds:SignedInfo`, replaces the upstream request body,
   updates `Content-Length`, and removes body-digest headers that no longer
   describe the signed body.

The body is serialized as UTF-8. Requests with an explicit non-UTF-8 `charset`
are rejected.

The generated security header has this general structure:

```xml
<wsse:Security soap:mustUnderstand="...">
  <wsu:Timestamp wsu:Id="TS-...">
    <wsu:Created>...</wsu:Created>
    <wsu:Expires>...</wsu:Expires>
  </wsu:Timestamp>
  <wsse:BinarySecurityToken wsu:Id="X509-...">...</wsse:BinarySecurityToken>
  <ds:Signature>
    <ds:SignedInfo>
      <ds:Reference URI="#Body-...">...</ds:Reference>
      <ds:Reference URI="#TS-...">...</ds:Reference>
    </ds:SignedInfo>
    <ds:SignatureValue>...</ds:SignatureValue>
    <ds:KeyInfo>
      <wsse:SecurityTokenReference>
        <wsse:Reference URI="#X509-..." ValueType="...#X509v3"/>
      </wsse:SecurityTokenReference>
    </ds:KeyInfo>
  </ds:Signature>
</wsse:Security>
```

## Requirements

- APISIX must run on Linux with `libxml2.so.2` available. The APISIX Debian
  images include this library.
- The certificate and private key must be PEM encoded, use RSA, and form a
  matching key pair.
- The SOAP service must support X.509 BinarySecurityToken direct references
  and exclusive XML canonicalization.
- Configure the Plugin after any other Plugin that modifies the SOAP body or
  signed headers. Any later modification invalidates the signature.

## Attributes

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `credentials` | object | True | | Signing credentials. |
| `credentials.certificate` | string | True | | PEM-encoded X.509 certificate or an APISIX Secret reference. |
| `credentials.private_key` | string | True | | PEM-encoded RSA private key or an APISIX Secret reference. |
| `signature` | object | False | `{}` | Signature configuration. |
| `signature.algorithm` | string | False | `rsa-sha256` | Signature and reference digest algorithm. Valid values are `rsa-sha256` and `rsa-sha1`. |
| `signature.key_info` | string | False | `binary_security_token` | Key information mode. Use `binary_security_token` for a direct X.509 token reference or `none` to omit both `ds:KeyInfo` and the token. |
| `soap.version` | string | False | `auto` | SOAP version: `auto`, `1.1`, or `1.2`. |
| `soap.must_understand` | boolean | False | `true` | Value of the SOAP `mustUnderstand` attribute on the Security header. |
| `timestamp.ttl_seconds` | integer | False | `300` | Timestamp lifetime. Valid range: 1 to 86400 seconds. |
| `request.methods` | array[string] | False | `["POST"]` | Request methods to sign. Other methods pass through unchanged. |
| `request.content_types` | array[string] | False | `["text/xml", "application/soap+xml", "application/xml"]` | Accepted media types. An explicit non-UTF-8 `charset` is rejected. |
| `request.max_body_bytes` | integer | False | `5242880` | Maximum request body size in bytes. Valid range: 1024 to 67108864. |

NOTE: `encrypt_fields = {"credentials.private_key"}` is defined in the
schema, so a directly configured private key is encrypted in etcd. Using
[APISIX Secret](../terminology/secret.md) references is recommended so key
material is not stored in Route configuration.

### Signature algorithms

| Value | SignatureMethod URI | DigestMethod URI | Usage |
| --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | Default and recommended. |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | Legacy WS-Security compatibility only. |

:::warning

SHA-1 is cryptographically weak and should only be enabled when a legacy SOAP
service cannot validate RSA-SHA256 signatures. APISIX logs a warning whenever
it signs a request with `rsa-sha1`. Use TLS, restrict network access, rotate
credentials regularly, and plan migration to RSA-SHA256.

:::

### SOAP version behavior

| `soap.version` | Behavior |
| --- | --- |
| `auto` | Accept SOAP 1.1 or SOAP 1.2 and derive attributes from the Envelope namespace. |
| `1.1` | Require `http://schemas.xmlsoap.org/soap/envelope/`. `mustUnderstand` is serialized as `1` or `0`. |
| `1.2` | Require `http://www.w3.org/2003/05/soap-envelope`. `mustUnderstand` is serialized as `true` or `false`. |

## Configure credentials

Use [APISIX Secret](../terminology/secret.md) references to keep private key
material out of Route configuration. The format is:

```text
$secret://<manager>/<configuration-id>/<key-path>
```

For example:

```json
{
  "credentials": {
    "certificate": "$secret://vault/signing/soap/certificate",
    "private_key": "$secret://vault/signing/soap/private-key"
  }
}
```

APISIX resolves references before the Plugin executes. Parsed credentials are
cached per worker using a fingerprint of the resolved values. Rotated Secret
values are used when the APISIX Secret cache refreshes; a worker restart is not
required.

### Use environment variables

Without an external secret manager, such as on Kubernetes, expose the PEM
values as environment variables and reference them with `$env://<NAME>`.

1. Create a Kubernetes Secret and inject it into the APISIX Pod:

   ```shell
   kubectl create secret generic soap-signing \
     --from-file=cert=signer.crt --from-file=key=signer.key
   ```

   ```yaml
   env:
     - name: SIGNER_CERT
       valueFrom: { secretKeyRef: { name: soap-signing, key: cert } }
     - name: SIGNER_KEY
       valueFrom: { secretKeyRef: { name: soap-signing, key: key } }
   ```

2. Allow the variables in the NGINX workers in `config.yaml`:

   ```yaml
   nginx_config:
     envs:
       - SIGNER_CERT
       - SIGNER_KEY
   ```

3. Reference them in the Plugin:

   ```json
   {
     "credentials": {
       "certificate": "$env://SIGNER_CERT",
       "private_key": "$env://SIGNER_KEY"
     }
   }
   ```

Changed environment values require restarting the APISIX Pods.

## Enable Plugin

The following example enables SOAP version auto-detection and RSA-SHA256:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-soap",
  "plugins": {
    "soap-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/soap/certificate",
        "private_key": "$secret://vault/signing/soap/private-key"
      },
      "signature": {"algorithm": "rsa-sha256"},
      "soap": {"version": "auto", "must_understand": true},
      "timestamp": {"ttl_seconds": 300}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

For a legacy service that only accepts SHA-1, use:

```json
{
  "signature": {"algorithm": "rsa-sha1"}
}
```

This changes both Body/Timestamp digests and the SignedInfo signature. It does
not change canonicalization or the BinarySecurityToken format.

## Disable KeyInfo

Set `signature.key_info` to `none` when the SOAP service already has the signing
certificate and expects no `ds:KeyInfo`. In this mode, the Plugin also omits
`wsse:BinarySecurityToken` because no generated element references it. The Body
and Timestamp remain signed.

The Plugin still requires both credentials: the private key signs the message
and the certificate validates that the configured key pair matches.

The following Admin API request creates a SOAP Route without KeyInfo:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-soap-without-key-info",
  "plugins": {
    "soap-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/soap/certificate",
        "private_key": "$secret://vault/signing/soap/private-key"
      },
      "signature": {
        "algorithm": "rsa-sha256",
        "key_info": "none"
      },
      "soap": {"version": "auto", "must_understand": true},
      "timestamp": {"ttl_seconds": 300}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

The resulting `wsse:Security` header contains the Timestamp and `ds:Signature`,
including references to the Body and Timestamp, but contains no
`wsse:BinarySecurityToken` or `ds:KeyInfo`. The upstream must select the trusted
verification certificate through its own configuration.

## Example usage

Send a SOAP 1.2 request:

```shell
curl http://127.0.0.1:9080/signed-soap \
  -H "Content-Type: application/soap+xml" \
  -d '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><Ping/></s:Body></s:Envelope>'
```

For SOAP 1.1, use `Content-Type: text/xml` and the SOAP 1.1 Envelope namespace:

```shell
curl http://127.0.0.1:9080/signed-soap \
  -H "Content-Type: text/xml; charset=utf-8" \
  -d '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><Ping/></s:Body></s:Envelope>'
```

The upstream receives the original SOAP message with a signed WS-Security
header. Requests whose method is not listed in `request.methods` pass through
unchanged.

## Error responses

| HTTP status | Message | Cause |
| --- | --- | --- |
| `400` | `empty_body` | The selected request has no body. |
| `400` | `invalid_soap` | XML parsing failed, Body is absent or duplicated, Header is duplicated or follows the Body, recognized XML ID values (`wsu:Id`, `xml:id`, and unqualified `Id`) are duplicated, the `wsse:Security` header already contains a `wsu:Timestamp`, or a DTD/entity declaration is present. |
| `400` | `not_soap` | The root is not a supported SOAP Envelope or does not match `soap.version`. |
| `400` | `already_signed` | The message already contains a `ds:Signature`. |
| `413` | `body_too_large` | The body exceeds `request.max_body_bytes`. |
| `415` | `unsupported_media_type` | The selected method uses a Content-Type not listed in `request.content_types` or declares a non-UTF-8 charset. |
| `500` | `credential_error` | A Secret could not be resolved, PEM parsing failed, the key is not RSA, or the certificate and key do not match. |
| `500` | `signing_error` | ID generation, canonicalization, digest generation, signing, or serialization failed. |

Detailed cryptographic and request content is not returned to clients.

## Limitations

- Only the SOAP Body and generated Timestamp are signed. Custom SOAP headers
  cannot currently be added as signature targets.
- KeyInfo can use an X.509 BinarySecurityToken direct reference or be omitted.
  Other KeyInfo formats are not supported.
- Actor/role targeting, thumbprint references, ECDSA, RSA-PSS, and replacing
  existing signatures are not supported.
- The complete request body is buffered before signing; signing is not a
  streaming operation.

## Troubleshooting

- If the service reports a digest mismatch, confirm no lower-priority Plugin or
  upstream proxy modifies the Body, Timestamp, namespace declarations, or IDs.
- If APISIX returns `not_soap`, compare `soap.version` with the Envelope
  namespace rather than relying only on Content-Type.
- If APISIX returns `credential_error`, verify the Secret URI, PEM boundaries,
  RSA key type, and certificate/private-key match.
- If a legacy service rejects RSA-SHA256, compare its expected algorithm URIs
  with the table above before enabling `rsa-sha1`.
- If the service rejects `mustUnderstand`, verify whether it expects SOAP 1.1
  numeric values or SOAP 1.2 boolean values.

## Delete Plugin

Remove `soap-signer` from the Route Plugin configuration and update the Route
through the Admin API. APISIX applies the change without a restart.
