---
title: xml-signer
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - XMLDSig
  - XML signature
description: The xml-signer Plugin applies an enveloped XML Digital Signature to an XML request body.
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

The `xml-signer` Plugin applies an enveloped
[XML Digital Signature](https://www.w3.org/TR/xmldsig-core1/) to an XML request
body before proxying it upstream. The generated signature covers the complete
XML document, excluding the generated `ds:Signature` element through the
enveloped-signature transform.

The Plugin supports RSA-SHA256 for normal use and RSA-SHA1 for interoperability
with legacy systems. It uses exclusive XML canonicalization without comments.
By default, it includes the configured X.509 certificate in `ds:KeyInfo`; this
element can be omitted when the verifier obtains the certificate out of band.

Use exactly one of `xml-signer` and `soap-signer` for a request. SOAP is XML,
and both plugins can accept `application/xml`; enabling both causes the second
plugin to reject the already-signed message.

## How it works

For a matching request, the Plugin performs the following operations during the
rewrite phase:

1. Buffers the request body up to `request.max_body_bytes`.
2. Parses the XML with external network access disabled.
3. Rejects DTD and entity declarations and documents that already contain a
   `ds:Signature` element.
4. Applies exclusive XML canonicalization to the document.
5. Calculates the reference digest selected by `signature.algorithm`.
6. Creates an enveloped `ds:Signature` under the document root.
7. Adds X.509 `ds:KeyInfo` unless `signature.key_info` is `none`.
8. Canonicalizes and signs `ds:SignedInfo` with the configured RSA private key.
9. Replaces the upstream request body, updates `Content-Length`, and removes
   body-digest headers that no longer describe the signed body.

The body is serialized as UTF-8 after signing. Insignificant formatting such as
indentation or quote style can therefore differ from the original request.
Requests with an explicit non-UTF-8 `charset` are rejected.

The generated signature has the following structure:

```xml
<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
  <ds:SignedInfo>
    <ds:CanonicalizationMethod
      Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
    <ds:SignatureMethod Algorithm="..."/>
    <ds:Reference URI="">
      <ds:Transforms>
        <ds:Transform
          Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        <ds:Transform
          Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      </ds:Transforms>
      <ds:DigestMethod Algorithm="..."/>
      <ds:DigestValue>...</ds:DigestValue>
    </ds:Reference>
  </ds:SignedInfo>
  <ds:SignatureValue>...</ds:SignatureValue>
  <ds:KeyInfo>
    <ds:X509Data><ds:X509Certificate>...</ds:X509Certificate></ds:X509Data>
  </ds:KeyInfo>
</ds:Signature>
```

## Requirements

- APISIX must run on Linux with `libxml2.so.2` available. The APISIX Debian
  images include this library.
- The certificate and private key must be PEM encoded, use RSA, and form a
  matching key pair.
- The upstream verifier must support exclusive XML canonicalization.
- Configure the Plugin after any other Plugin that modifies the request body.
  Any later body modification invalidates the signature.

## Attributes

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `credentials` | object | True | | Signing credentials. |
| `credentials.certificate` | string | True | | PEM-encoded X.509 certificate or an APISIX Secret reference. |
| `credentials.private_key` | string | True | | PEM-encoded RSA private key or an APISIX Secret reference. |
| `signature` | object | False | `{}` | Signature configuration. |
| `signature.algorithm` | string | False | `rsa-sha256` | Signature and reference digest algorithm. Valid values are `rsa-sha256` and `rsa-sha1`. |
| `signature.key_info` | string | False | `x509_data` | Key information included in the signature. Use `x509_data` to embed the certificate or `none` to omit `ds:KeyInfo`. |
| `request.methods` | array[string] | False | `["POST"]` | Request methods to sign. Other methods pass through unchanged. |
| `request.content_types` | array[string] | False | `["application/xml", "text/xml"]` | Accepted media types. Parameters are ignored except that an explicit non-UTF-8 `charset` is rejected. |
| `request.max_body_bytes` | integer | False | `5242880` | Maximum request body size in bytes. Valid range: 1024 to 67108864. |

NOTE: `encrypt_fields = {"credentials.private_key"}` is defined in the
schema, so a directly configured private key is encrypted in etcd. Using
[APISIX Secret](../terminology/secret.md) references is recommended so key
material is not stored in Route configuration.

### Signature algorithms

| Value | SignatureMethod URI | DigestMethod URI | Usage |
| --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | Default and recommended. |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | Legacy compatibility only. |

:::warning

SHA-1 is cryptographically weak and should only be enabled when a legacy
upstream cannot validate RSA-SHA256 signatures. APISIX logs a warning whenever
it signs a request with `rsa-sha1`. Use compensating controls such as TLS,
restricted network access, short credential rotation intervals, and a migration
plan to RSA-SHA256.

:::

## Configure credentials

You can configure PEM values directly, but Secret references keep private key
material out of Route configuration. The reference format is:

```text
$secret://<manager>/<configuration-id>/<key-path>
```

For example, after creating an APISIX Vault Secret resource named `signing`, a
certificate and key can be referenced as follows:

```json
{
  "credentials": {
    "certificate": "$secret://vault/signing/xml/certificate",
    "private_key": "$secret://vault/signing/xml/private-key"
  }
}
```

APISIX resolves references before the Plugin executes. Parsed credentials are
cached per worker using a fingerprint of the resolved values. When the Secret
cache returns rotated PEM values, the Plugin parses and uses the new key pair
without requiring an APISIX worker restart.

### Use environment variables

Without an external secret manager, such as on Kubernetes, expose the PEM
values as environment variables and reference them with `$env://<NAME>`.

1. Create a Kubernetes Secret and inject it into the APISIX Pod:

   ```shell
   kubectl create secret generic xml-signing \
     --from-file=cert=signer.crt --from-file=key=signer.key
   ```

   ```yaml
   env:
     - name: SIGNER_CERT
       valueFrom: { secretKeyRef: { name: xml-signing, key: cert } }
     - name: SIGNER_KEY
       valueFrom: { secretKeyRef: { name: xml-signing, key: key } }
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

The following example enables RSA-SHA256 signing on a Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml",
  "plugins": {
    "xml-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/xml/certificate",
        "private_key": "$secret://vault/signing/xml/private-key"
      },
      "signature": {"algorithm": "rsa-sha256"},
      "request": {"max_body_bytes": 5242880}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

To communicate with a legacy system that only accepts SHA-1, change the
signature configuration:

```json
{
  "signature": {"algorithm": "rsa-sha1"}
}
```

No other configuration changes are required. Both `SignatureMethod` and
`DigestMethod` are changed together to prevent mixed-algorithm signatures.

## Disable KeyInfo

Set `signature.key_info` to `none` when the upstream verifier already has the
signing certificate and requires a signature without `ds:KeyInfo`. The Plugin
still requires both credentials: the private key signs the document and the
certificate is used to validate that the configured key pair matches.

The following Admin API request creates a Route that emits no `ds:KeyInfo`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml-without-key-info",
  "plugins": {
    "xml-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/xml/certificate",
        "private_key": "$secret://vault/signing/xml/private-key"
      },
      "signature": {
        "algorithm": "rsa-sha256",
        "key_info": "none"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

The resulting XML still contains `ds:SignedInfo`, `ds:SignatureValue`, and the
document digest, but contains no `ds:KeyInfo` or embedded certificate. The
upstream must select the trusted verification certificate through its own
configuration.

## Example usage

Send an XML request:

```shell
curl http://127.0.0.1:9080/signed-xml \
  -H "Content-Type: application/xml" \
  -d '<order xmlns="urn:example"><id>42</id></order>'
```

The upstream receives the body with one enveloped `ds:Signature` under the
document root. Requests whose method is not listed in `request.methods` pass
through unchanged.

## Error responses

| HTTP status | Message | Cause |
| --- | --- | --- |
| `400` | `empty_body` | The selected request has no body. |
| `400` | `invalid_xml` | XML parsing failed, the document has no root, or a DTD/entity declaration is present. |
| `400` | `already_signed` | The document already contains a `ds:Signature`. |
| `413` | `body_too_large` | The body exceeds `request.max_body_bytes`. |
| `415` | `unsupported_media_type` | The selected method uses a Content-Type not listed in `request.content_types` or declares a non-UTF-8 charset. |
| `500` | `credential_error` | A Secret could not be resolved, PEM parsing failed, the key is not RSA, or the certificate and key do not match. |
| `500` | `signing_error` | Canonicalization, digest generation, signing, or serialization failed. |

Detailed cryptographic and request content is not returned to clients.

## Limitations

- Only enveloped whole-document signatures with `Reference URI=""` are
  supported.
- `KeyInfo` can contain X.509 data or be omitted. Other KeyInfo formats are not
  supported.
- Detached signatures, XPath transforms, ECDSA, RSA-PSS, and re-signing an
  already signed document are not supported.
- The complete request body is buffered in memory or a temporary request-body
  file before signing; this is not a streaming transform.

## Troubleshooting

- If the upstream reports a digest mismatch, confirm no Plugin with a lower
  priority changes the body after `xml-signer`.
- If APISIX returns `credential_error`, verify the Secret URI, PEM boundaries,
  RSA key type, and certificate/private-key match.
- If a legacy verifier rejects the signature, compare its required algorithm
  URIs with the table above and confirm it supports exclusive C14N.
- If requests return `415`, include the XML media type in
  `request.content_types` or correct the client Content-Type header.

## Delete Plugin

Remove `xml-signer` from the Route Plugin configuration and update the Route
through the Admin API. APISIX applies the change without a restart.
