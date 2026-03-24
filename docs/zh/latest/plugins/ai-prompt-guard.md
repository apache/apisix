---
title: ai-prompt-guard
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-guard
description: ai-prompt-guard 插件通过检查和验证传入的提示词消息来保护你的 AI 端点。
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

## 描述

`ai-prompt-guard` 插件通过检查和验证传入的提示词消息来保护你的 AI 端点。它根据用户定义的白名单和黑名单模式检查请求内容，以确保仅处理批准的输入。根据其配置，该插件可以仅检查最新消息或整个对话历史，并且可以设置为检查所有角色的提示词或仅检查最终用户的提示词。

当同时配置了 **allow**（允许）和 **deny**（拒绝）模式时，插件首先确保至少匹配一个允许模式。如果没有匹配，请求将被拒绝，并返回 _"Request doesn't match allow patterns"_ 错误。如果找到允许模式，则会检查是否存在任何拒绝模式——如果检测到，则拒绝请求并返回 _"Request contains prohibited content"_ 错误。

## 插件属性

| **字段**                          | **是否必填** | **类型**  | **描述**                                                                                                                                                      |
| ------------------------------ | ------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| match_all_roles                | 否           | boolean   | 如果为 true，则验证所有角色的消息。如果为 false，则仅验证 `user` 角色的消息。默认值为 `false`。 |
| match_all_conversation_history | 否           | boolean   | 如果为 true，则连接并检查对话历史中的所有消息。如果为 false，则仅检查最后一条消息的内容。默认值为 `false`。 |
| allow_patterns                 | 否           | array     | 一个正则表达式模式数组，消息应与之匹配。配置后，消息必须至少匹配一个模式才能被视为有效。              |
| deny_patterns                  | 否           | array     | 一个正则表达式模式数组，消息不应与之匹配。如果消息匹配任何模式，则请求应被拒绝。如果同时配置了 `allow_patterns` 和 `deny_patterns`，插件首先确保至少匹配一个 `allow_patterns`。              |

## 示例

以下示例将使用 OpenAI 作为上游服务提供商。在继续之前，请创建一个 [OpenAI 账户](https://openai.com) 和一个 [API 密钥](https://openai.com/blog/openai-api)。你可以选择将密钥保存到环境变量中，如下所示：

```shell
export OPENAI_API_KEY=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   # 替换为你的 API 密钥
```

如果你使用的是其他 LLM 提供商，请参阅该提供商的文档以获取 API 密钥。

### 实现允许和拒绝模式

以下示例演示了如何使用 `ai-prompt-guard` 插件通过定义允许和拒绝模式来验证用户提示词，并了解允许模式的优先级。

定义允许和拒绝模式。你可以选择将它们保存到环境变量中以便于转义：

```shell
# 允许美元金额
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
# 拒绝美国号码格式的电话号码
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一条路由，使用 `ai-proxy` 代理到 OpenAI，并使用 `ai-prompt-guard` 检查输入提示词：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-prompt-guard-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      # highlight-start
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
      # highlight-end
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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
            Authorization: "Bearer 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"
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

将配置应用到你的集群：

```shell
kubectl apply -f ai-prompt-guard-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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
                Authorization: "Bearer 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"
            options:
              model: gpt-4
```

将配置应用到你的集群：

```shell
kubectl apply -f ai-prompt-guard-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送请求，评估购买的性价比：

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

你应该会收到类似于以下的 `HTTP/1.1 200 OK` 响应：

```json
{
  ...
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        # highlight-next-line
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

向路由发送另一条消息中不包含任何价格的请求：

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

你应该会收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request doesn't match allow patterns"}
```

向路由发送第三条消息中包含电话号码的请求：

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

你应该会收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request contains prohibited content"}
```

默认情况下，该插件仅检查 `user` 角色的输入和最后一条消息。例如，如果你发送一个包含禁止内容的 `system` 提示词请求：

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

你将收到 `HTTP/1.1 200 OK` 响应。

如果你发送一个包含禁止内容的倒数第二条消息的请求：

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

你也将收到 `HTTP/1.1 200 OK` 响应。

请参阅[下一个示例](#validate-messages-from-all-roles-and-conversation-history)了解如何检查所有角色的消息和所有消息。

### 验证所有角色和对话历史中的消息

以下示例演示了如何使用 `ai-prompt-guard` 插件验证所有角色（如 `system` 和 `user`）的提示词，并验证整个对话历史而不是最后一条消息。

定义允许和拒绝模式。你可以选择将它们保存到环境变量中以便于转义：

```shell
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一条路由，使用 `ai-proxy` 代理到 OpenAI，并使用 `ai-prompt-guard` 检查输入提示词：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-prompt-guard-route",
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

<TabItem value="adc">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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
            Authorization: "Bearer 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"
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

将配置应用到你的集群：

```shell
kubectl apply -f ai-prompt-guard-history-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

创建一条路由，并配置 `ai-prompt-guard` 和 [`ai-proxy`](/hub/ai-proxy) 插件如下：

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
                Authorization: "Bearer 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"
            options:
              model: gpt-4
```

将配置应用到你的集群：

```shell
kubectl apply -f ai-prompt-guard-history-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

发送一个包含禁止内容的 `system` 提示词的请求：

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

你应该会收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
{"message":"Request contains prohibited content"}
```

发送一个包含同一角色多个消息且包含禁止内容的请求：

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

你应该会收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

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
      { "role": "system", "content": "The puchase is made in El Paso." },
      { "role": "user", "content": "Customer John contact: xxx-xxx-xxxx" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee." }
    ]
  }'
```

你应该会收到类似于以下的 `HTTP/1.1 200 OK` 响应：

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
