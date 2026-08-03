---
title: jwe-decrypt
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - JWE Decrypt
  - jwe-decrypt
description: The jwe-decrypt Plugin decrypts JWE authorization headers in requests directed to Routes or Services, enhancing API security.
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

The `jwe-decrypt` Plugin decrypts [JWE](https://datatracker.ietf.org/doc/html/rfc7516) authorization headers in requests sent to APISIX [Routes](../terminology/route.md) or [Services](../terminology/service.md).

The decryption key should be configured in [Consumer](../terminology/consumer.md).

## Attributes

### Consumer

| Name              | Type    | Required | Default | Valid values   | Description                                                                                                                                                                                                                              |
| ----------------- | ------- | -------- | ------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| key               | string  | True     |         |                | A unique key that identifies the Credential for a Consumer.                                                                                                                                                                              |
| secret            | string  | True     |         | 32 characters  | The shared symmetric encryption/decryption key. You can also store it in an environment variable and reference it using the `env://` prefix, or in a secret manager such as HashiCorp Vault's KV secrets engine, and reference it using the `secret://` prefix. |
| is_base64_encoded | boolean | False    | false   |                | Set to true if the secret is base64 encoded. Note that after enabling `is_base64_encoded`, the `secret` length may exceed 32 characters. You only need to make sure the decoded length is still 32 characters.                       |

### Route or Service

| Name           | Type    | Required | Default       | Valid values | Description                                                                                                                       |
| -------------- | ------- | -------- | ------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| header         | string  | True     | Authorization |              | The header to get the token from.                                                                                                 |
| forward_header | string  | True     | Authorization |              | Name of the header that passes the plaintext to the Upstream.                                                                     |
| strict         | boolean | False    | true          |              | If true, throw a 403 error if JWE token is missing from the request. If false, do not throw an error when JWE token is not found. |

## Examples

The examples below demonstrate how you can work with the `jwe-decrypt` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Create a Consumer with the Decryption Key

The following example demonstrates how to create a Consumer with the decryption key and generate a JWE token for it.

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

To generate a JWE token for the Consumer, encrypt the payload offline with any AES-256-GCM library, using the Consumer secret as the key. The token structure is:

```text
base64url(header).<empty>.base64url(iv).base64url(ciphertext).base64url(tag)
```

where the header is `{"alg":"dir","enc":"A256GCM","kid":"<consumer-key>"}`. The IV must be unique and randomly generated for every token; never reuse an IV with the same key.

For example, the following token encrypts the payload `{"uid":10000,"uname":"test"}` for the Consumer key `jack-key` with the secret configured above:

```text
eyJraWQiOiJqYWNrLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..vi29KBCQKcVmPwTT.VToyPMFbq-ZY05MIpntP1N3AmYeq3zELQ0B6iQ.vuTPG2ODc-DjUTjNCzfA2A
```

### Decrypt Data with JWE

The following example demonstrates how to decrypt the JWE token generated above.

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
      "nodes": {
        "httpbin.org:80": 1
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
      nodes:
        - host: httpbin.org
          port: 80
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

Send a request to the Route with the JWE encrypted data in the `Authorization` header:

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
