---
title: ai-prompt-guard
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-guard
description: 本文档包含有关 Apache APISIX ai-prompt-guard 插件的信息。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-prompt-guard" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-prompt-guard` 插件通过检查和验证传入的提示消息来保护您的 LLM 端点。它根据用户定义的允许和拒绝模式检查请求内容，确保只有经过批准的输入才会被转发到上游 LLM。根据其配置，该插件可以仅检查最新消息或整个对话历史，并且可以设置为检查所有角色的提示或仅检查最终用户的提示。

当同时配置了 `allow_patterns` 和 `deny_patterns` 时，插件首先确保至少匹配一个 `allow_patterns`。如果没有匹配，请求将被拒绝。如果匹配了允许的模式，它会继续检查是否存在任何拒绝模式的匹配。

## 插件属性

| **字段** | **必选** | **类型** | **描述** |
| --- | --- | --- | --- |
| `match_all_roles` | 否 | boolean | 如果为 `true`，验证所有角色的消息。如果为 `false`，仅验证 `user` 角色的消息。默认值：`false`。 |
| `match_all_conversation_history` | 否 | boolean | 如果为 `true`，连接并检查对话历史中的所有消息。如果为 `false`，仅检查最后一条消息的内容。默认值：`false`。 |
| `allow_patterns` | 否 | array | 消息应匹配的正则表达式模式数组。配置后，消息必须至少匹配一个模式才被视为有效。默认值：`[]`。 |
| `deny_patterns` | 否 | array | 消息不应匹配的正则表达式模式数组。如果消息匹配任何模式，请求将被拒绝。如果同时配置了 `allow_patterns` 和 `deny_patterns`，插件会首先确保至少匹配一个 `allow_patterns`。默认值：`[]`。 |

## 使用示例

以下示例将使用 OpenAI 作为上游服务提供商。在继续之前，请创建一个 [OpenAI 账户](https://openai.com)和一个 [API 密钥](https://openai.com/blog/openai-api)。您可以选择将密钥保存到环境变量中：

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

如果您使用其他 LLM 提供商，请参阅提供商的文档以获取 API 密钥。

### 实现允许和拒绝模式

以下示例演示了如何使用 `ai-prompt-guard` 插件通过定义允许和拒绝模式来验证用户提示，以及如何理解允许模式的优先级。

定义允许和拒绝模式。您可以选择将它们保存到环境变量中以便于转义：

```shell
# 允许美元金额
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
# 拒绝美国电话号码格式
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

:::note

您可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建一个路由，使用 [ai-proxy](./ai-proxy.md) 代理到 OpenAI 并使用 `ai-prompt-guard` 检查输入提示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        }
      },
      "ai-prompt-guard": {
        "allow_patterns": [
          "'"$ALLOW_PATTERN_1"'"
        ],
        "deny_patterns": [
          "'"$DENY_PATTERN_1"'"
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由：

```yaml title="adc.yaml"
services:
  - name: prompt-guard-service
    routes:
      - name: prompt-guard-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-prompt-guard:
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由：

```yaml title="ai-prompt-guard-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-guard-plugin-config
spec:
  plugins:
    - name: ai-prompt-guard
      config:
        allow_patterns:
          - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
        deny_patterns:
          - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-prompt-guard-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由：

```yaml title="ai-prompt-guard-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-guard-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-prompt-guard
          enable: true
          config:
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-prompt-guard-ic.yaml
```

</TabItem>
</Tabs>

向路由发送一个请求，评估购买的公平性：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 200 OK` 响应，类似如下：

```json
{
  ...
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The purchase is not at a decent price. Typically, a hot brewed coffee costs anywhere from $1 to $3 in most places in the US, so $12.5 is quite expensive.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

发送另一个不包含任何价格的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John paid a bit for a hot brewed coffee in El Paso." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request doesn't match allow patterns"}
```

发送第三个包含电话号码的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John (647-200-9393) paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request contains prohibited content"}
```

默认情况下，插件仅检查 `user` 角色的输入和最后一条消息。例如，如果您发送一个在 `system` 提示中包含禁止内容的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase from 647-200-9393 is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您将收到一个 `HTTP/1.1 200 OK` 响应。

如果您发送一个在倒数第二条消息中包含禁止内容的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "Customer John contact: 647-200-9393" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您也将收到一个 `HTTP/1.1 200 OK` 响应。

参阅[下一个示例](#验证所有角色的消息和对话历史)了解如何检查所有角色和所有消息。

### 验证所有角色的消息和对话历史

以下示例演示了如何使用 `ai-prompt-guard` 插件验证所有角色（如 `system` 和 `user`）的提示，以及验证整个对话历史而不是仅验证最后一条消息。

定义允许和拒绝模式。您可以选择将它们保存到环境变量中以便于转义：

```shell
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建一个路由，使用 [ai-proxy](./ai-proxy.md) 代理到 OpenAI 并使用 `ai-prompt-guard` 检查输入提示。将 `match_all_roles` 和 `match_all_conversation_history` 设置为 `true` 以验证所有角色的消息和整个对话：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        }
      },
      "ai-prompt-guard": {
        "match_all_roles": true,
        "match_all_conversation_history": true,
        "allow_patterns": [
          "'"$ALLOW_PATTERN_1"'"
        ],
        "deny_patterns": [
          "'"$DENY_PATTERN_1"'"
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由。将 `match_all_roles` 和 `match_all_conversation_history` 设置为 `true` 以验证所有角色的消息和整个对话：

```yaml title="adc.yaml"
services:
  - name: prompt-guard-service
    routes:
      - name: prompt-guard-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-prompt-guard:
            match_all_roles: true
            match_all_conversation_history: true
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由。将 `match_all_roles` 和 `match_all_conversation_history` 设置为 `true` 以验证所有角色的消息和整个对话：

```yaml title="ai-prompt-guard-history-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-guard-plugin-config
spec:
  plugins:
    - name: ai-prompt-guard
      config:
        match_all_roles: true
        match_all_conversation_history: true
        allow_patterns:
          - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
        deny_patterns:
          - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-prompt-guard-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建一个配置了 `ai-prompt-guard` 和 [ai-proxy](./ai-proxy.md) 插件的路由。将 `match_all_roles` 和 `match_all_conversation_history` 设置为 `true` 以验证所有角色的消息和整个对话：

```yaml title="ai-prompt-guard-history-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-guard-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-prompt-guard
          enable: true
          config:
            match_all_roles: true
            match_all_conversation_history: true
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-prompt-guard-history-ic.yaml
```

</TabItem>
</Tabs>

发送一个在 `system` 提示中包含禁止内容的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase from 647-200-9393 is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request contains prohibited content"}
```

发送一个来自同一角色的多条包含禁止内容的消息的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "Customer John contact: 647-200-9393" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request contains prohibited content"}
```

发送一个符合模式的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "system", "content": "The purchase is made in El Paso." },
      { "role": "user", "content": "Customer John contact: xxx-xxx-xxxx" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee." }
    ]
  }'
```

您应该收到一个 `HTTP/1.1 200 OK` 响应，类似如下：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "$12.5 is generally considered quite expensive for a cup of brew coffee.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```
