---
title: jwe-decrypt
keywords:
  - Apache APISIX
  - API 网关
  - APISIX 插件
  - JWE Decrypt
  - jwe-decrypt
description: jwe-decrypt 插件解密发送到路由或服务的请求中的 JWE 授权请求头，增强 API 安全性。
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

## 描述

`jwe-decrypt` 插件解密发送到 APISIX [路由](../terminology/route.md)或[服务](../terminology/service.md)的请求中的 [JWE](https://datatracker.ietf.org/doc/html/rfc7516) 授权请求头。

该插件添加了一个 `/apisix/plugin/jwe/encrypt` 内部端点用于 JWE 加密。解密时，密钥应配置在[消费者](../terminology/consumer.md)中。

## 属性

### 消费者

| 名称              | 类型    | 必选项 | 默认值 | 有效值    | 描述                                                                                                                                                                                          |
| ----------------- | ------- | ------ | ------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| key               | string  | 是     |        |           | 用于标识消费者凭证的唯一密钥。                                                                                                                                                                |
| secret            | string  | 是     |        | 32 个字符 | 加密密钥。也可以将其存储在环境变量中并使用 `env://` 前缀引用，或存储在 HashiCorp Vault 的 KV 密钥引擎等密钥管理器中并使用 `secret://` 前缀引用。启用 `is_base64_encoded` 后，`secret` 长度可能超过 32 个字符，只需确保解码后长度仍为 32 个字符即可。 |
| is_base64_encoded | boolean | 否     | false  |           | 如果密钥为 Base64 编码，则设置为 true。                                                                                                                                                       |

### 路由或服务

| 名称           | 类型    | 必选项 | 默认值        | 有效值 | 描述                                                                                           |
| -------------- | ------- | ------ | ------------- | ------ | ---------------------------------------------------------------------------------------------- |
| header         | string  | 是     | Authorization |        | 用于获取令牌的请求头。                                                                         |
| forward_header | string  | 是     | Authorization |        | 传递明文给上游的请求头名称。                                                                   |
| strict         | boolean | 否     | true          |        | 如果为 true，当请求中缺少 JWE 令牌时抛出 403 错误。如果为 false，当找不到 JWE 令牌时不抛出错误。 |

## 使用示例

以下示例演示了如何针对不同场景使用 `jwe-decrypt` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### 暴露 JWE 加密端点并生成 JWE 令牌

以下示例演示如何暴露 JWE 加密端点并生成 JWE 令牌。

`jwe-decrypt` 插件在 `/apisix/plugin/jwe/encrypt` 创建一个内部端点用于 JWE 加密。使用 [public-api](public-api.md) 插件暴露该端点：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/jwe-encrypt-api" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/apisix/plugin/jwe/encrypt",
    "plugins": {
      "public-api": {}
    }
  }'
```

创建带有 `jwe-decrypt` 的消费者并配置解密密钥：

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

暴露 JWE 加密端点并创建带有 `jwe-decrypt` 凭证的消费者：

```yaml title="adc.yaml"
consumers:
  - username: jack
    plugins:
      jwe-decrypt:
        key: jack-key
        secret: key-length-should-be-32-chars123
services:
  - name: jwe-encrypt-api-service
    routes:
      - name: jwe-encrypt-api-route
        uris:
          - /apisix/plugin/jwe/encrypt
        plugins:
          public-api: {}
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="ingress-controller" label="Ingress Controller">

创建带有 `jwe-decrypt` 的消费者并使用 `public-api` 插件暴露 JWE 加密端点：

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="jwe-encrypt-api-ic.yaml"
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
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: jwe-encrypt-api-plugin-config
spec:
  plugins:
    - name: public-api
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwe-encrypt-api-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /apisix/plugin/jwe/encrypt
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: jwe-encrypt-api-plugin-config
```

将配置应用到集群：

```shell
kubectl apply -f jwe-encrypt-api-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

`ApisixConsumer` 仅通过 `authParameter` 字段支持认证插件，而 `jwe-decrypt` 不在支持的类型中。此示例无法使用 APISIX Ingress Controller 完成。

</TabItem>
</Tabs>

</TabItem>
</Tabs>

向加密端点发送请求，使用消费者密钥加密 payload 中的示例数据：

```shell
curl "http://127.0.0.1:9080/apisix/plugin/jwe/encrypt?key=jack-key" \
  -d 'payload={"uid":10000,"uname":"test"}' -G
```

您应该看到类似以下的响应，响应体中包含 JWE 加密数据：

```text
eyJraWQiOiJqYWNrLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.IUFW_q4igO_wvf63i-3VwV0MEetPL9C20tlgcQ.fveViMUi0ijJlQ19D7kDrg
```

### 使用 JWE 解密数据

以下示例演示如何解密上述生成的 JWE 令牌。

创建带有 `jwe-decrypt` 的路由以解密授权请求头：

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

将配置同步到网关：

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

将配置应用到集群：

```shell
kubectl apply -f jwe-decrypt-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

`ApisixConsumer` 仅通过 `authParameter` 字段支持认证插件，而 `jwe-decrypt` 不在支持的类型中。此示例无法使用 APISIX Ingress Controller 完成。

</TabItem>
</Tabs>

</TabItem>
</Tabs>

在 `Authorization` 请求头中携带 JWE 加密数据向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything/jwe" -H 'Authorization: eyJraWQiOiJqYWNrLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.IUFW_q4igO_wvf63i-3VwV0MEetPL9C20tlgcQ.fveViMUi0ijJlQ19D7kDrg'
```

您应该看到类似以下的响应，其中 `Authorization` 请求头显示了 payload 的明文：

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
