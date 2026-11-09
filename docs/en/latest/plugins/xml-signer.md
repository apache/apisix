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
By default, it includes the configured X.509 certificate in `ds:KeyInfo`.
You can omit this element when the verifier obtains the certificate out of band.

Do not combine this Plugin with another request-signing Plugin on the same
Route. The Plugin rejects documents that already contain an XML signature.

:::caution

The Plugin signs every well-formed XML document that reaches it with the
configured private key. By default (`request.require_consumer` is `true`), it
only signs requests that an authentication Plugin, such as
[`key-auth`](key-auth.md) or [`jwt-auth`](jwt-auth.md), attributed to a
Consumer, and answers `401` otherwise. Authentication Plugins run before
`xml-signer`. An `anonymous_consumer` configured on the authentication Plugin
also satisfies this check, so do not configure one on signing Routes. Set
`request.require_consumer` to `false` only when the Route is protected in
another way, for example by mTLS, `ip-restriction`, or `forward-auth`.

:::

## How It Works

For a matching request, the Plugin performs the following operations during the
rewrite phase:

1. Rejects the request with `401` unless an authentication Plugin attributed
   it to a Consumer, when `request.require_consumer` is `true`.
2. Buffers the request body up to `request.max_body_bytes`.
3. Parses the XML with external network access disabled.
4. Rejects DTD and entity declarations and documents that already contain a
   `ds:Signature` element.
5. Applies exclusive XML canonicalization to the document. Declared prefixes
   that text or attribute values refer to, such as `ns` in
   `xsi:type="ns:Type"`, are listed in an `ec:InclusiveNamespaces`
   `PrefixList`, so that their bindings are signed too.
6. Calculates the reference digest selected by `signature.algorithm`.
7. Creates an enveloped `ds:Signature` under the document root.
8. Adds X.509 `ds:KeyInfo` unless `signature.key_info` is `none`.
9. Canonicalizes and signs `ds:SignedInfo` with the configured RSA private key.
10. Replaces the upstream request body, updates `Content-Length`, and removes
   body-digest headers that no longer describe the signed body.

The Plugin only accepts UTF-8 encoded documents and serializes the body as
UTF-8 after signing. Insignificant formatting such as indentation or quote
style can therefore differ from the original request. The Plugin ignores the
`encoding` in the XML declaration, rejects UTF-16, UTF-32, and other encodings
with `invalid_xml`, and rejects requests with an explicit non-UTF-8 `charset`.

Decode compressed request bodies before signing, for example with the
[`request-decompress`](request-decompress.md) Plugin. The signing Plugin
rejects a remaining Content-Encoding other than `identity`.

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

- APISIX must run on Linux with `libxml2.so.2` available. The released APISIX
  Debian, Ubuntu, and Red Hat images include this library. Images built from
  source, for example with `debian-dev/Dockerfile.local` from
  [apisix-docker](https://github.com/apache/apisix-docker), do not; install it
  in the final image, for example with `apt-get install -y libxml2`. Without
  the library, APISIX logs `xml-signer is unavailable and will reject
  requests` at startup and the Plugin returns `500 signing_error`.
- APISIX-Runtime must be built to enforce `request.max_body_bytes` while NGINX
  reads the request body.
- The certificate and private key must be PEM encoded, use RSA, and form a
  matching key pair. The RSA key must be at least 2048 bits for `rsa-sha256`
  and at least 1024 bits for `rsa-sha1`.
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
| `request.require_consumer` | boolean | False | `true` | Sign only requests that an authentication Plugin attributed to a Consumer; other requests receive `401`. Set to `false` only when the Route is protected in another way. |
| `request.max_body_bytes` | integer | False | `5242880` | Maximum request body size in bytes. Valid range: 1024 to 67108864. The Plugin never raises the limit above a non-zero `nginx_config.http.client_max_body_size` or a `client-control` `max_body_size` configured on the Route; the smaller value applies. |

NOTE: The schema declares `encrypt_fields = {"credentials.private_key"}`.
APISIX encrypts a directly configured private key in etcd only when you enable
`apisix.data_encryption.enable_encrypt_fields` and configure a valid keyring.
This does not encrypt standalone YAML configuration. Use
[APISIX Secret](../terminology/secret.md) references to keep key material out of
Route configuration.

### Signature Algorithms

| Value | SignatureMethod URI | DigestMethod URI | Minimum RSA key size | Usage |
| --- | --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | 2048 bits | Default and recommended. |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | 1024 bits | Legacy compatibility only. Accepts 1024-bit keys still used by some legacy systems. |

:::warning

SHA-1 is cryptographically weak. Enable it only when a legacy upstream cannot
validate RSA-SHA256 signatures. APISIX logs a warning whenever
it signs a request with `rsa-sha1`. Use compensating controls such as TLS,
restricted network access, short credential rotation intervals, and a migration
plan to RSA-SHA256.

:::

## Configure Credentials

You can configure PEM values directly, but Secret references keep private key
material out of Route configuration. The reference format is:

```text
$secret://<manager>/<configuration-id>/<key-path>
```

For example, after creating an APISIX Vault Secret resource named `signing`,
you can reference a certificate and key as follows:

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

### Use Environment Variables

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

Create a Consumer that clients authenticate as, for example with
[`key-auth`](key-auth.md):

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "username": "signer_client",
  "plugins": {
    "key-auth": {"key": "signer-client-key"}
  }
}'
```

The following example enables RSA-SHA256 signing on a Route that requires
`key-auth`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml",
  "plugins": {
    "key-auth": {},
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
still requires both credentials: it uses the private key to sign the document
and the certificate to validate that the configured key pair matches.

The following Admin API request creates a Route that emits no `ds:KeyInfo`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml-without-key-info",
  "plugins": {
    "key-auth": {},
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

## Example Usage

Send an XML request:

```shell
curl http://127.0.0.1:9080/signed-xml \
  -H "apikey: signer-client-key" \
  -H "Content-Type: application/xml" \
  -d '<order xmlns="urn:example"><id>42</id></order>'
```

The upstream receives the body with one enveloped `ds:Signature` under the
document root. Requests whose method is not listed in `request.methods` pass
through unchanged. Requests without a valid key are rejected by `key-auth`
before they reach the Plugin.

## Error Responses

| HTTP status | Message | Cause |
| --- | --- | --- |
| `401` | `unauthorized` | `request.require_consumer` is `true` and no authentication Plugin attributed the request to a Consumer. |
| `400` | `empty_body` | The selected request has no body. |
| `400` | `invalid_xml` | XML parsing failed, the document is not UTF-8 encoded, the document is not namespace well-formed (for example, it uses an undeclared prefix), more than 8 declared prefixes are referenced in content, the document has no root, a DTD/entity declaration is present, or the document exceeds the parser limits listed under [Limitations](#limitations). |
| `400` | `already_signed` | The document already contains a `ds:Signature`. |
| `413` | `body_too_large` | The body exceeds the effective body size limit (see `request.max_body_bytes`). |
| `415` | `unsupported_media_type` | Content-Type is missing, repeated, not listed in `request.content_types`, or declares a non-UTF-8 charset; or Content-Encoding is repeated or is not `identity`. |
| `500` | `credential_error` | A Secret could not be resolved, PEM parsing failed, the key is not RSA or is shorter than the minimum size for `signature.algorithm`, or the certificate and key do not match. |
| `500` | `signing_error` | libxml2 is not available, or canonicalization, digest generation, signing, or serialization failed. |

The Plugin does not return detailed cryptographic or request content to clients.

## Limitations

- Only enveloped whole-document signatures with `Reference URI=""` are
  supported.
- `KeyInfo` can contain X.509 data or be omitted. Other KeyInfo formats are not
  supported.
- Detached signatures, XPath transforms, ECDSA, RSA-PSS, and re-signing an
  already signed document are not supported.
- The complete request body is buffered in memory or a temporary request-body
  file before signing; this is not a streaming transform.
- To keep parsing time linear, the Plugin rejects a document in which one
  element has more than 256 attributes (namespace declarations included) or
  more than 128 namespace declarations are in scope at once. Real documents
  stay far below these limits.
- Exclusive canonicalization only renders namespace declarations that element
  and attribute names use. When text or an attribute value refers to a
  declared prefix as `prefix:name`, such as `ns` in `xsi:type="ns:Type"`, the
  Plugin lists the prefix in the `ec:InclusiveNamespaces` `PrefixList` of the
  canonicalization transform, so that changing its binding, or adding a new
  declaration for it on an intermediate element, invalidates the signature.
  The verifier must support this parameter, which is part of the Exclusive XML
  Canonicalization specification. Because libxml2 checks every listed prefix
  on every element, a document that refers to more than 8 declared prefixes in
  content is rejected. Unprefixed names in content, which would resolve
  against the default namespace, are not protected this way.
- The signing certificate's validity period is not enforced. APISIX logs a
  warning when it loads a certificate that has expired or is not yet valid,
  because verifiers reject such signatures.

## Troubleshooting

- If APISIX logs `xml-signer is unavailable and will reject requests:
  libxml2 is not available` and requests return `500 signing_error`, install
  `libxml2` in the APISIX image or host and restart APISIX.
- If the upstream reports a digest mismatch, confirm no Plugin with a lower
  priority changes the body after `xml-signer`.
- If APISIX returns `credential_error`, verify the Secret URI, PEM boundaries,
  RSA key type and size (2048 bits for `rsa-sha256`, 1024 bits for
  `rsa-sha1`), and certificate/private-key match.
- If a legacy verifier rejects the signature, compare its required algorithm
  URIs with the table above and confirm it supports exclusive C14N.
- If requests return `415`, include the XML media type in
  `request.content_types` or correct the client Content-Type header.

## Delete Plugin

Remove `xml-signer` from the Route Plugin configuration and update the Route
through the Admin API. APISIX applies the change without a restart.
