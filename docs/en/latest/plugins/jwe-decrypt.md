---
title: jwe-decrypt
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - JWE Decrypt
  - jwe-decrypt
description: The jwe-decrypt Plugin decrypts its supported five-part compact token format and forwards the plaintext in a configured request header.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/jwe-decrypt" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `jwe-decrypt` Plugin reads a five-part compact token from a request header, selects a [Consumer](../terminology/consumer.md) by the token's `kid`, decrypts the ciphertext with AES-256-GCM, and writes the plaintext to a configured header before proxying the request. You can enable the Plugin on APISIX [Routes](../terminology/route.md) or [Services](../terminology/service.md).

The token resembles [JWE Compact Serialization](https://datatracker.ietf.org/doc/html/rfc7516#section-3.1), but the current Plugin uses a Plugin-specific format. Configure a 32-byte decryption secret on the Consumer.

:::warning

The current implementation reads `kid` from the decoded header but does not validate the `alg` or `enc` fields and does not use the protected-header segment as AES-GCM additional authenticated data (AAD). Standard RFC 7516 JWE libraries are therefore not directly interoperable. Generate tokens with the exact format described below, use a fixed trusted token generator, and do not treat header fields as authenticated.

:::

:::caution

The decrypted plaintext is forwarded in a request header. For sensitive plaintext, do not rely on an HTTPS Upstream alone: APISIX does not verify server certificates for standard HTTP Upstreams. Send the request over an authenticated, protected network path, such as through a proxy or service mesh that validates the upstream server's identity. Restrict access to the upstream and avoid logging the configured forwarding header.

:::

## Attributes

### Consumer

| Name              | Type    | Required | Default | Valid values   | Description                                                                                                                              |
| ----------------- | ------- | -------- | ------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| key               | string  | True     |         |                | A unique key that identifies the Credential for a Consumer.                                                                              |
| secret            | string  | True     |         | 32 bytes       | A shared symmetric key. Use a [secret reference](../terminology/secret.md), such as `$env://...` or `$secret://...`.                     |
| is_base64_encoded | boolean | False    | false   |                | Set to true if the secret is base64url encoded. The decoded secret must still be 32 bytes.                                               |

### Route or Service

| Name           | Type    | Required | Default       | Valid values | Description                                                                                                                       |
| -------------- | ------- | -------- | ------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| header         | string  | True     | Authorization |              | The header to get the token from.                                                                                                 |
| forward_header | string  | True     | Authorization |              | Name of the header that passes the plaintext to the Upstream.                                                                     |
| strict         | boolean | False    | true          |              | If true, return a 403 error when the encrypted plugin token is missing. If false, continue when the token is not found.           |

## Examples

The examples below demonstrate how you can work with the `jwe-decrypt` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Create a Consumer with the Decryption Key

The following example demonstrates how to create a Consumer with the decryption key and generate an encrypted plugin token for it.

Create a Consumer with `jwe-decrypt` and configure the decryption key:

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "plugins": {
      "jwe-decrypt": {
        "key": "jack-key",
        "secret": "key-length-should-be-32-chars123"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc" label="ADC">

Create a Consumer with `jwe-decrypt` Credential:

```yaml title="adc.yaml"
consumers:
  - username: jack
    plugins:
      jwe-decrypt:
        key: jack-key
        secret: key-length-should-be-32-chars123
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="ingress-controller" label="Ingress Controller">

Create a Consumer with `jwe-decrypt`:

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="jwe-consumer-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  plugins:
    - name: jwe-decrypt
      config:
        key: jack-key
        secret: key-length-should-be-32-chars123
```

Apply the configuration to your cluster:

```shell
kubectl apply -f jwe-consumer-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

`ApisixConsumer` only supports authentication plugins via the `authParameter` field, and `jwe-decrypt` is not among the supported types. This example cannot be completed using the APISIX Ingress Controller.

</TabItem>
</Tabs>

</TabItem>
</Tabs>

To generate a token for the Consumer, encrypt the payload offline with AES-256-GCM without protected-header AAD, using the Consumer secret as the key. Standard RFC 7516 libraries normally authenticate the protected header as AAD and are not directly interoperable with this Plugin. Use the following exact token structure:

```text
base64url(header).<empty>.base64url(iv).base64url(ciphertext).base64url(tag)
```

where the header is `{"alg":"dir","enc":"A256GCM","kid":"<consumer-key>"}`. The fields describe the intended algorithm and identify the Consumer, but the current Plugin does not authenticate or validate them. The IV must be unique and randomly generated for every token; never reuse an IV with the same key.

For example, the following token encrypts the payload `{"uid":10000,"uname":"test"}` for the Consumer key `jack-key` with the secret configured above:

```text
eyJraWQiOiJqYWNrLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..vi29KBCQKcVmPwTT.VToyPMFbq-ZY05MIpntP1N3AmYeq3zELQ0B6iQ.vuTPG2ODc-DjUTjNCzfA2A
```

### Decrypt Data from the Plugin Token

The following example demonstrates how to decrypt the plugin token generated above.

Create a Route with `jwe-decrypt` to decrypt the authorization header:

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwe-decrypt-route",
    "uri": "/anything/jwe",
    "plugins": {
      "jwe-decrypt": {
        "header": "Authorization",
        "forward_header": "Authorization"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "nodes": {
        "httpbin.org:443": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: jwe-decrypt-service
    routes:
      - name: jwe-decrypt-route
        uris:
          - /anything/jwe
        plugins:
          jwe-decrypt:
            header: Authorization
            forward_header: Authorization
    upstream:
      type: roundrobin
      scheme: https
      nodes:
        - host: httpbin.org
          port: 443
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="ingress-controller" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

The following Gateway API configuration uses public HTTPBin only with the non-sensitive demonstration payload shown on this page. Before forwarding real decrypted data, replace it with a controlled upstream and use an authenticated, protected network path. An APISIX HTTPS Upstream does not validate the upstream server certificate by itself; use a proxy or service mesh that validates the upstream server's identity.

```yaml title="jwe-decrypt-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: jwe-decrypt-plugin-config
spec:
  plugins:
    - name: jwe-decrypt
      config:
        header: Authorization
        forward_header: Authorization
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwe-decrypt-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything/jwe
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: jwe-decrypt-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f jwe-decrypt-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

`ApisixConsumer` only supports authentication plugins via the `authParameter` field, and `jwe-decrypt` is not among the supported types. This example cannot be completed using the APISIX Ingress Controller.

</TabItem>
</Tabs>

</TabItem>
</Tabs>

Send a request to the Route with the encrypted plugin token in the `Authorization` header:

```shell
curl "http://127.0.0.1:9080/anything/jwe" -H 'Authorization: eyJraWQiOiJqYWNrLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..vi29KBCQKcVmPwTT.VToyPMFbq-ZY05MIpntP1N3AmYeq3zELQ0B6iQ.vuTPG2ODc-DjUTjNCzfA2A'
```

You should see a response similar to the following, where the `Authorization` header shows the plaintext of the payload:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "{\"uid\":10000,\"uname\":\"test\"}",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.1.2",
    "X-Amzn-Trace-Id": "Root=1-6510f2c3-1586ec011a22b5094dbe1896",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 119.143.79.94",
  "url": "http://127.0.0.1/anything/jwe"
}
```
