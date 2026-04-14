---
title: ai-rate-limiting
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-rate-limiting
  - AI
  - LLM
description: ai-rate-limiting 插件对发送到 LLM 服务的请求实施基于令牌的速率限制，防止过度使用，优化 API 消费，并确保高效的资源分配。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-rate-limiting" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-rate-limiting` 插件对发送到 LLM 服务的请求实施基于令牌的速率限制。它通过控制在指定时间范围内消耗的令牌数量来帮助管理 API 使用，确保公平的资源分配并防止服务过载。它通常与 [`ai-proxy`](./ai-proxy.md) 或 [`ai-proxy-multi`](./ai-proxy-multi.md) 插件一起使用。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| limit | integer | False | | >0 | 在给定时间间隔内允许的最大令牌数。`limit` 和 `instances.limit` 中至少应配置一个。如果未配置 `rules`，则为必填项。 |
| time_window | integer | False | | >0 | 与速率限制 `limit` 对应的时间间隔（秒）。`time_window` 和 `instances.time_window` 中至少应配置一个。如果未配置 `rules`，则为必填项。 |
| show_limit_quota_header | boolean | False | true | | 如果为 true，则在响应中包含速率限制头部。当未设置 `rules` 时，头部为 `X-AI-RateLimit-Limit-*`、`X-AI-RateLimit-Remaining-*` 和 `X-AI-RateLimit-Reset-*`，其中 `*` 是实例名称。当设置了 `rules` 时，详见 `rules.header_prefix`。 |
| limit_strategy | string | False | total_tokens | [`total_tokens`, `prompt_tokens`, `completion_tokens`, `expression`] | 应用速率限制的令牌类型。`total_tokens` 是 `prompt_tokens` 和 `completion_tokens` 的总和。当设置为 `expression` 时，使用 `cost_expr` 字段动态计算令牌消耗。 |
| cost_expr | string | 否 | | | 用于动态计算令牌消耗的 Lua 算术表达式。变量从 LLM API 原始使用量响应字段注入。缺失的变量默认为 0。仅在 `limit_strategy` 为 `expression` 时有效。示例：`input_tokens + cache_creation_input_tokens + output_tokens`。 |
| instances | array[object] | 否 | | | LLM 实例速率限制配置。 |
| instances.name | string | 是 | | | LLM 服务实例的名称。 |
| instances.limit | integer | 是 | | >0 | 实例在给定时间间隔内允许的最大令牌数。 |
| instances.time_window | integer | 是 | | >0 | 实例速率限制 `limit` 对应的时间间隔（秒）。 |
| rejected_code | integer | 否 | 503 | [200, 599] | 当超出配额的请求被拒绝时返回的 HTTP 状态码。 |
| rejected_msg | string | 否 | | | 当超出配额的请求被拒绝时返回的响应体。 |
| rules | array[object] | 否 | | | 按顺序应用的速率限制规则数组。如果配置了此项，则优先于 `limit` 和 `time_window`。 |
| rules.count | integer 或 string | 是 | | >0 或变量表达式 | 在给定时间间隔内允许的最大令牌数。可以是静态整数或变量表达式，如 `$http_custom_limit`。 |
| rules.time_window | integer 或 string | 是 | | >0 或变量表达式 | 与速率限制 `count` 对应的时间间隔（秒）。可以是静态整数或变量表达式。 |
| rules.key | string | 是 | | | 用于计数请求的键。如果配置的键不存在，则不会执行该规则。`key` 被解释为变量组合。所有变量应以美元符号（`$`）为前缀。例如：`$http_custom_a $http_custom_b`。 |
| rules.header_prefix | string | 否 | | | 速率限制响应头部的前缀。配置后，前缀插入到头部名称中 `X-AI-` 之后。例如，将 `header_prefix` 设置为 `test` 时，头部变为 `X-AI-Test-RateLimit-Limit`、`X-AI-Test-RateLimit-Remaining` 和 `X-AI-Test-RateLimit-Reset`。未配置时，使用规则在数组中的索引作为前缀。例如，第一条规则的头部为 `X-AI-1-RateLimit-Limit`、`X-AI-1-RateLimit-Remaining` 和 `X-AI-1-RateLimit-Reset`。 |

## 示例

以下示例演示了如何为不同场景配置 `ai-rate-limiting`。

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 与 `ai-proxy` 一起应用速率限制

以下示例演示了如何使用 `ai-proxy` 代理 LLM 流量，并使用 `ai-rate-limiting` 在实例上配置基于令牌的速率限制。

创建一个 Route 并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

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
        "options": {
          "model": "gpt-35-turbo-instruct",
          "max_tokens": 512,
          "temperature": 1.0
        }
      },
      "ai-rate-limiting": {
        "limit": 300,
        "time_window": 30,
        "limit_strategy": "prompt_tokens"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
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
              model: gpt-35-turbo-instruct
              max_tokens: 512
              temperature: 1.0
          ai-rate-limiting:
            limit: 300
            time_window: 30
            limit_strategy: prompt_tokens
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-35-turbo-instruct
          max_tokens: 512
          temperature: 1.0
    - name: ai-rate-limiting
      config:
        limit: 300
        time_window: 30
        limit_strategy: prompt_tokens
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rate-limiting-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-35-turbo-instruct
              max_tokens: 512
              temperature: 1.0
        - name: ai-rate-limiting
          enable: true
          config:
            limit: 300
            time_window: 30
            limit_strategy: prompt_tokens
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

向 Route 发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1 + 1 equals 2. This is a fundamental arithmetic operation where adding one unit to another results in a total of two units."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

如果在 30 秒窗口内消耗了 300 个提示令牌的速率限制配额，所有额外的请求将被拒绝。

### 对多个实例中的一个进行速率限制

以下示例演示了如何使用 `ai-proxy-multi` 配置两个模型进行负载均衡，将 80% 的流量转发到一个实例，20% 转发到另一个实例。此外，使用 `ai-rate-limiting` 对接收 80% 流量的实例配置基于令牌的速率限制，这样当配置的配额完全消耗时，额外的流量将被转发到另一个实例。

创建一个 Route，对 `deepseek-instance-1` 实例应用 30 秒窗口内 100 个总令牌的速率限制配额，并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "deepseek-instance-1",
            "provider": "deepseek",
            "weight": 8,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          },
          {
            "name": "deepseek-instance-2",
            "provider": "deepseek",
            "weight": 2,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "limit_strategy": "total_tokens",
        "instances": [
          {
            "name": "deepseek-instance-1",
            "limit": 100,
            "time_window": 30
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy-multi:
            instances:
              - name: deepseek-instance-1
                provider: deepseek
                weight: 8
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
              - name: deepseek-instance-2
                provider: deepseek
                weight: 2
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
          ai-rate-limiting:
            limit_strategy: total_tokens
            instances:
              - name: deepseek-instance-1
                limit: 100
                time_window: 30
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: ai-proxy-multi
      config:
        instances:
          - name: deepseek-instance-1
            provider: deepseek
            weight: 8
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
          - name: deepseek-instance-2
            provider: deepseek
            weight: 2
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
    - name: ai-rate-limiting
      config:
        limit_strategy: total_tokens
        instances:
          - name: deepseek-instance-1
            limit: 100
            time_window: 30
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rate-limiting-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-proxy-multi
          enable: true
          config:
            instances:
              - name: deepseek-instance-1
                provider: deepseek
                weight: 8
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: deepseek-chat
              - name: deepseek-instance-2
                provider: deepseek
                weight: 2
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: deepseek-chat
        - name: ai-rate-limiting
          enable: true
          config:
            limit_strategy: total_tokens
            instances:
              - name: deepseek-instance-1
                limit: 100
                time_window: 30
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

向 Route 发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1 + 1 equals 2. This is a fundamental arithmetic operation where adding one unit to another results in a total of two units."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

如果 `deepseek-instance-1` 实例在 30 秒窗口内消耗了 100 个令牌的速率限制配额，额外的请求将全部转发到未设置速率限制的 `deepseek-instance-2`。

### 对所有实例应用相同配额

以下示例演示了如何对 `ai-rate-limiting` 中的所有 LLM 上游实例应用相同的速率限制配额。

为了演示和更容易区分，您将配置一个 OpenAI 实例和一个 DeepSeek 实例作为上游 LLM 服务。

创建一个 Route，对所有实例在 60 秒窗口内应用 100 个总令牌的速率限制配额，并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "limit": 100,
        "time_window": 60,
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy-multi:
            instances:
              - name: openai-instance
                provider: openai
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${OPENAI_API_KEY}"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
          ai-rate-limiting:
            limit: 100
            time_window: 60
            rejected_code: 429
            limit_strategy: total_tokens
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: ai-proxy-multi
      config:
        instances:
          - name: openai-instance
            provider: openai
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
          - name: deepseek-instance
            provider: deepseek
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
    - name: ai-rate-limiting
      config:
        limit: 100
        time_window: 60
        rejected_code: 429
        limit_strategy: total_tokens
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rate-limiting-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-proxy-multi
          enable: true
          config:
            instances:
              - name: openai-instance
                provider: openai
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: deepseek-chat
        - name: ai-rate-limiting
          enable: true
          config:
            limit: 100
            time_window: 60
            rejected_code: 429
            limit_strategy: total_tokens
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

向 Route 发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到来自任一 LLM 实例的响应，类似以下内容：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure! Sir Isaac Newton formulated three laws of motion that describe the motion of objects. These laws are widely used in physics and engineering for studying and understanding how things move. Here they are:\n\n1. Newton's First Law - Law of Inertia: An object at rest tends to stay at rest and an object in motion tends to stay in motion with the same speed and in the same direction unless acted upon by an unbalanced force. This is also known as the principle of inertia.\n\n2. Newton's Second Law of Motion - Force and Acceleration: The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. This is usually formulated as F=ma where F is the force applied, m is the mass of the object and a is the acceleration produced.\n\n3. Newton's Third Law - Action and Reaction: For every action, there is an equal and opposite reaction. This means that any force exerted on a body will create a force of equal magnitude but in the opposite direction on the object that exerted the first force.\n\nIn simple terms: \n1. If you slide a book on a table and let go, it will stop because of the friction (or force) between it and the table.\n2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 256,
    "total_tokens": 279,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了配置的 `100` 配额，预期在 60 秒窗口内的下一个请求将被转发到另一个实例。

在同一个 60 秒窗口内，向 Route 发送另一个 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到来自另一个 LLM 实例的响应，类似以下内容：

```json
{
  ...
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics. Here's an explanation of each law:\n\n---\n\n### **1. Newton's First Law (Law of Inertia)**\n- **Statement**: An object will remain at rest or in uniform motion in a straight line unless acted upon by an external force.\n- **What it means**: This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion. If no net force acts on an object, its velocity (speed and direction) will not change.\n- **Example**: A book lying on a table will stay at rest unless you push it. Similarly, a hockey puck sliding on ice will keep moving at a constant speed unless friction or another force slows it down.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration)**\n- **Statement**: The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n"
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 13,
    "completion_tokens": 256,
    "total_tokens": 269,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 13
  },
  "system_fingerprint": "fp_3a5770e1b4_prod0225"
}
```

由于 `total_tokens` 值超过了配置的 `100` 配额，预期在 60 秒窗口内的下一个请求将被拒绝。

在同一个 60 秒窗口内，向 Route 发送第三个 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到 `HTTP 429 Too Many Requests` 响应并观察到以下头部：

```text
X-AI-RateLimit-Limit-openai-instance: 100
X-AI-RateLimit-Remaining-openai-instance: 0
X-AI-RateLimit-Reset-openai-instance: 0
X-AI-RateLimit-Limit-deepseek-instance: 100
X-AI-RateLimit-Remaining-deepseek-instance: 0
X-AI-RateLimit-Reset-deepseek-instance: 0
```

### 配置实例优先级和速率限制

以下示例演示了如何配置两个具有不同优先级的模型，并对具有较高优先级的实例应用速率限制。在 `fallback_strategy` 设置为 `["rate_limiting"]` 的情况下，一旦高优先级实例的速率限制配额完全消耗，插件应继续将请求转发到低优先级实例。

创建一个 Route，对 `openai-instance` 实例设置速率限制和更高的优先级，并将 `fallback_strategy` 设置为 `["rate_limiting"]`。更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "fallback_strategy": ["rate_limiting"],
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "priority": 1,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "priority": 0,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "openai-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy-multi:
            fallback_strategy:
              - rate_limiting
            instances:
              - name: openai-instance
                provider: openai
                priority: 1
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${OPENAI_API_KEY}"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                priority: 0
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
          ai-rate-limiting:
            instances:
              - name: openai-instance
                limit: 10
                time_window: 60
            limit_strategy: total_tokens
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: ai-proxy-multi
      config:
        fallback_strategy:
          - rate_limiting
        instances:
          - name: openai-instance
            provider: openai
            priority: 1
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
          - name: deepseek-instance
            provider: deepseek
            priority: 0
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
    - name: ai-rate-limiting
      config:
        instances:
          - name: openai-instance
            limit: 10
            time_window: 60
        limit_strategy: total_tokens
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rate-limiting-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-proxy-multi
          enable: true
          config:
            fallback_strategy:
              - rate_limiting
            instances:
              - name: openai-instance
                provider: openai
                priority: 1
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                priority: 0
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: deepseek-chat
        - name: ai-rate-limiting
          enable: true
          config:
            instances:
              - name: openai-instance
                limit: 10
                time_window: 60
            limit_strategy: total_tokens
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

向 Route 发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1+1 equals 2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 8,
    "total_tokens": 31,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了配置的 `10` 配额，预期在 60 秒窗口内的下一个请求将被转发到另一个实例。

在同一个 60 秒窗口内，向 Route 发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newton law" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Certainly! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics.\n\n---\n\n### **1. Newton's First Law (Law of Inertia):**\n- **Statement:** An object at rest will remain at rest, and an object in motion will continue moving at a constant velocity (in a straight line at a constant speed), unless acted upon by an external force.\n- **Key Idea:** This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion.\n- **Example:** If you slide a book across a table, it eventually stops because of the force of friction acting on it. Without friction, the book would keep moving indefinitely.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration):**\n- **Statement:** The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n  where:\n  - \\( F \\) = net force applied (in Newtons),\n  -"
      },
      ...
    }
  ],
  ...
}
```

### 按 Consumer 进行负载均衡和速率限制

以下示例演示了如何配置两个模型进行负载均衡，并按 Consumer 应用速率限制。

创建 Consumer `johndoe` 并对 `openai-instance` 实例设置 60 秒窗口内 10 个令牌的速率限制配额：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "plugins": {
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "openai-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

为 `johndoe` 配置 `key-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建另一个 Consumer `janedoe` 并对 `deepseek-instance` 实例设置 60 秒窗口内 10 个令牌的速率限制配额：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "janedoe",
    "plugins": {
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "deepseek-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

为 `janedoe` 配置 `key-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/janedoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

创建一个 Route 并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "key-auth": {},
      "ai-proxy-multi": {
        "fallback_strategy": ["rate_limiting"],
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建两个 Consumer 和一个启用按 Consumer 速率限制的 Route：

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    plugins:
      ai-rate-limiting:
        instances:
          - name: openai-instance
            limit: 10
            time_window: 60
        rejected_code: 429
        limit_strategy: total_tokens
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: john-key
  - username: janedoe
    plugins:
      ai-rate-limiting:
        instances:
          - name: deepseek-instance
            limit: 10
            time_window: 60
        rejected_code: 429
        limit_strategy: total_tokens
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jane-key
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          key-auth: {}
          ai-proxy-multi:
            fallback_strategy:
              - rate_limiting
            instances:
              - name: openai-instance
                provider: openai
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${OPENAI_API_KEY}"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建两个 Consumer 和一个启用按 Consumer 速率限制的 Route：

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: john-key
  plugins:
    - name: ai-rate-limiting
      config:
        instances:
          - name: openai-instance
            limit: 10
            time_window: 60
        rejected_code: 429
        limit_strategy: total_tokens
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: janedoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jane-key
  plugins:
    - name: ai-rate-limiting
      config:
        instances:
          - name: deepseek-instance
            limit: 10
            time_window: 60
        rejected_code: 429
        limit_strategy: total_tokens
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: ai-proxy-multi
      config:
        fallback_strategy:
          - rate_limiting
        instances:
          - name: openai-instance
            provider: openai
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
          - name: deepseek-instance
            provider: deepseek
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

:::note

ApisixConsumer CRD 目前不支持在 Consumer 上配置除 `authParameter` 中允许的认证插件之外的其他插件。此示例无法使用 APISIX CRD 完成。

:::

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

向 Route 发送不带任何 Consumer 密钥的 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到 `HTTP/1.1 401 Unauthorized` 响应。

使用 `johndoe` 的密钥向 Route 发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: john-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1+1 equals 2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 8,
    "total_tokens": 31,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了 `johndoe` 的 `openai` 实例配置配额，预期在 60 秒窗口内来自 `johndoe` 的下一个请求将被转发到 `deepseek` 实例。

在同一个 60 秒窗口内，使用 `johndoe` 的密钥向 Route 发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: john-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws to me" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Certainly! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics.\n\n---\n\n### **1. Newton's First Law (Law of Inertia):**\n- **Statement:** An object at rest will remain at rest, and an object in motion will continue moving at a constant velocity (in a straight line at a constant speed), unless acted upon by an external force.\n- **Key Idea:** This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion.\n- **Example:** If you slide a book across a table, it eventually stops because of the force of friction acting on it. Without friction, the book would keep moving indefinitely.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration):**\n- **Statement:** The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n  where:\n  - \\( F \\) = net force applied (in Newtons),\n  -"
      },
      ...
    }
  ],
  ...
}
```

使用 `janedoe` 的密钥向 Route 发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: jane-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The sum of 1 and 1 is 2. This is a basic arithmetic operation where you combine two units to get a total of two units."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 14,
    "completion_tokens": 31,
    "total_tokens": 45,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 14
  },
  "system_fingerprint": "fp_3a5770e1b4_prod0225"
}
```

由于 `total_tokens` 值超过了 `janedoe` 的 `deepseek` 实例配置配额，预期在 60 秒窗口内来自 `janedoe` 的下一个请求将被转发到 `openai` 实例。

在同一个 60 秒窗口内，使用 `janedoe` 的密钥向 Route 发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: jane-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws to me" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure, here are Newton's three laws of motion:\n\n1) Newton's First Law, also known as the Law of Inertia, states that an object at rest will stay at rest, and an object in motion will stay in motion, unless acted on by an external force. In simple words, this law suggests that an object will keep doing whatever it is doing until something causes it to do otherwise. \n\n2) Newton's Second Law states that the force acting on an object is equal to the mass of that object times its acceleration (F=ma). This means that force is directly proportional to mass and acceleration. The heavier the object and the faster it accelerates, the greater the force.\n\n3) Newton's Third Law, also known as the law of action and reaction, states that for every action, there is an equal and opposite reaction. Essentially, any force exerted onto a body will create a force of equal magnitude but in the opposite direction on the object that exerted the first force.\n\nRemember, these laws become less accurate when considering speeds near the speed of light (where Einstein's theory of relativity becomes more appropriate) or objects very small or very large. However, for everyday situations, they provide a good model of how things move.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

这显示了 `ai-proxy-multi` 根据 Consumer 在 `ai-rate-limiting` 中的速率限制规则对流量进行负载均衡。

### 按规则进行速率限制

以下示例演示了如何配置插件，根据请求属性应用不同的速率限制规则。在此示例中，速率限制基于表示调用者访问层级的 HTTP 头部值进行应用。所有规则按顺序执行。如果配置的键不存在，则跳过相应的规则。

创建一个带有 `ai-rate-limiting` 插件的路由，根据请求头部应用不同的速率限制，允许按订阅（`X-Subscription-ID`）进行速率限制，并对试用用户（`X-Trial-ID`）实施更严格的限制：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "fallback_strategy": ["rate_limiting"],
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "priority": 1,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "priority": 0,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "rejected_code": 429,
        "rules": [
          {
            "key": "${http_x_subscription_id}",
            "count": "${http_x_custom_count ?? 500}",
            "time_window": 60
          },
          {
            "key": "${http_x_trial_id}",
            "count": 50,
            "time_window": 60
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-rate-limiting-service
    routes:
      - name: ai-rate-limiting-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy-multi:
            fallback_strategy:
              - rate_limiting
            instances:
              - name: openai-instance
                provider: openai
                priority: 1
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${OPENAI_API_KEY}"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                priority: 0
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer ${DEEPSEEK_API_KEY}"
                options:
                  model: deepseek-chat
          ai-rate-limiting:
            rejected_code: 429
            rules:
              - key: "${http_x_subscription_id}"
                count: "${http_x_custom_count ?? 500}"
                time_window: 60
              - key: "${http_x_trial_id}"
                count: 50
                time_window: 60
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rate-limiting-plugin-config
spec:
  plugins:
    - name: ai-proxy-multi
      config:
        fallback_strategy:
          - rate_limiting
        instances:
          - name: openai-instance
            provider: openai
            priority: 1
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
          - name: deepseek-instance
            provider: deepseek
            priority: 0
            weight: 0
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: deepseek-chat
    - name: ai-rate-limiting
      config:
        rejected_code: 429
        rules:
          - key: "${http_x_subscription_id}"
            count: "${http_x_custom_count ?? 500}"
            time_window: 60
          - key: "${http_x_trial_id}"
            count: 50
            time_window: 60
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
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
            name: ai-rate-limiting-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-rate-limiting-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rate-limiting-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rate-limiting-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-proxy-multi
          enable: true
          config:
            fallback_strategy:
              - rate_limiting
            instances:
              - name: openai-instance
                provider: openai
                priority: 1
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: gpt-4
              - name: deepseek-instance
                provider: deepseek
                priority: 0
                weight: 0
                auth:
                  header:
                    Authorization: "Bearer your-api-key"
                options:
                  model: deepseek-chat
        - name: ai-rate-limiting
          enable: true
          config:
            rejected_code: 429
            rules:
              - key: "${http_x_subscription_id}"
                count: "${http_x_custom_count ?? 500}"
                time_window: 60
              - key: "${http_x_trial_id}"
                count: 50
                time_window: 60
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rate-limiting-ic.yaml
```

</TabItem>
</Tabs>

第一条规则使用 `X-Subscription-ID` 请求头部的值作为速率限制键，并根据 `X-Custom-Count` 头部动态设置请求限制。如果未提供该头部，则应用默认的 500 个令牌计数。第二条规则使用 `X-Trial-ID` 请求头部的值作为速率限制键，设置更严格的 50 个令牌限制。

要验证速率限制，使用相同的订阅 ID 向 Route 发送多个以下请求：

```shell
curl "http://127.0.0.1:9080/anything" -i -X POST \
  -H "X-Subscription-ID: sub-123456789" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

这些请求应匹配第一条规则，默认令牌计数为 500。您应该看到配额内的请求返回 `HTTP/1.1 200 OK`，而超出配额的请求返回 `HTTP/1.1 429 Too Many Requests`：

```text
HTTP/1.1 200 OK
...
X-AI-1-RateLimit-Limit: 500
X-AI-1-RateLimit-Remaining: 499
X-AI-1-RateLimit-Reset: 60

HTTP/1.1 429 Too Many Requests
...
X-AI-1-RateLimit-Limit: 500
X-AI-1-RateLimit-Remaining: 0
X-AI-1-RateLimit-Reset: 5.871000051498
```

等待时间窗口重置。使用相同的订阅 ID 向 Route 发送多个以下请求，并将 `X-Custom-Count` 头部设置为 10：

```shell
curl "http://127.0.0.1:9080/anything" -i -X POST \
  -H "X-Subscription-ID: sub-123456789" \
  -H "X-Custom-Count: 10" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

这些请求应匹配第一条规则，自定义令牌计数为 10。您应该看到配额内的请求返回 `HTTP/1.1 200 OK`，而超出配额的请求返回 `HTTP/1.1 429 Too Many Requests`：

```text
HTTP/1.1 200 OK
...
X-AI-1-RateLimit-Limit: 10
X-AI-1-RateLimit-Remaining: 9
X-AI-1-RateLimit-Reset: 60

HTTP/1.1 429 Too Many Requests
...
X-AI-1-RateLimit-Limit: 10
X-AI-1-RateLimit-Remaining: 0
X-AI-1-RateLimit-Reset: 40.422000169754
```

最后，使用试用 ID 向 Route 发送多个以下请求：

```shell
curl "http://127.0.0.1:9080/anything" -i -X POST \
  -H "X-Trial-ID: trial-123456789" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

这些请求应匹配第二条规则，令牌计数为 50。您应该看到配额内的请求返回 `HTTP/1.1 200 OK`，而超出配额的请求返回 `HTTP/1.1 429 Too Many Requests`：

```text
HTTP/1.1 200 OK
...
X-AI-2-RateLimit-Limit: 50
X-AI-2-RateLimit-Remaining: 49
X-AI-2-RateLimit-Reset: 60

HTTP/1.1 429 Too Many Requests
...
X-AI-2-RateLimit-Limit: 50
X-AI-2-RateLimit-Remaining: 0
X-AI-2-RateLimit-Reset: 44
```
