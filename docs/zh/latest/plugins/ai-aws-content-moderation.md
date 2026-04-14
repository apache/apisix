---
title: ai-aws-content-moderation
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-aws-content-moderation
  - AWS
  - 内容审核
description: 本文档包含有关 Apache APISIX ai-aws-content-moderation 插件的信息。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-aws-content-moderation" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-aws-content-moderation` 插件集成了 [AWS Comprehend](https://aws.amazon.com/comprehend/)，用于在代理请求到 LLM 时检查请求体中的有害内容，例如亵渎、仇恨言论、侮辱、骚扰、暴力等，如果评估结果超过配置的阈值则拒绝请求。

此插件只能在代理请求到 LLM 的路由中使用。

## 插件属性

| **字段** | **必选项** | **类型** | **描述** |
| --- | --- | --- | --- |
| `comprehend` | 是 | Object | [AWS Comprehend](https://aws.amazon.com/comprehend/) 配置。 |
| `comprehend.access_key_id` | 是 | String | AWS 访问密钥 ID。 |
| `comprehend.secret_access_key` | 是 | String | AWS 秘密访问密钥。 |
| `comprehend.region` | 是 | String | AWS 区域。 |
| `comprehend.endpoint` | 否 | String | AWS Comprehend 服务端点。必须匹配模式 `^https?://`。 |
| `comprehend.ssl_verify` | 否 | Boolean | 如果为 true，则启用 TLS 证书验证。默认值：`true`。 |
| `moderation_categories` | 否 | Object | 审核类别及其对应阈值的键值对。在每个键值对中，键应为 `PROFANITY`、`HATE_SPEECH`、`INSULT`、`HARASSMENT_OR_ABUSE`、`SEXUAL` 或 `VIOLENCE_OR_THREAT` 之一；阈值应在 0 到 1 之间（包含）。 |
| `moderation_threshold` | 否 | Number | 整体毒性阈值。值越高，允许的有害内容越多。此选项与 `moderation_categories` 中的单独类别阈值不同。例如，如果 `moderation_categories` 中设置了 `PROFANITY` 阈值为 `0.5`，而请求的 `PROFANITY` 分数为 `0.1`，则请求不会超过类别阈值。但如果请求的其他类别（如 `SEXUAL` 或 `VIOLENCE_OR_THREAT`）超过了 `moderation_threshold`，则请求将被拒绝。默认值：`0.5`。范围：0 - 1。 |

## 使用示例

以下示例使用 OpenAI 作为上游服务提供商。

开始之前，请创建一个 [OpenAI 账户](https://openai.com) 并获取 [API 密钥](https://openai.com/blog/openai-api)。如果您使用其他 LLM 提供商，请参阅该提供商的文档获取 API 密钥。

此外，创建 [AWS IAM 用户访问密钥](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html) 以便 APISIX 访问 [AWS Comprehend](https://aws.amazon.com/comprehend/)。

您可以选择将这些密钥保存到环境变量中：

```shell
export OPENAI_API_KEY=your-openai-api-key
export AWS_ACCESS_KEY=your-aws-access-key-id
export AWS_SECRET_ACCESS_KEY=your-aws-secret-access-key
```

### 审核亵渎内容

以下示例演示如何使用该插件审核提示中的亵渎程度。亵渎阈值设置为较低的值（`0.1`），以仅允许较低程度的亵渎。

:::note

您可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

使用 [`ai-proxy`](./ai-proxy.md) 插件创建一个到 LLM 聊天补全端点的路由，并在 `ai-aws-content-moderation` 中配置允许的亵渎级别：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$AWS_ACCESS_KEY"'",
          "secret_access_key": "'"$AWS_SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 0.1
        }
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "model": "gpt-4"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="adc.yaml"
services:
  - name: aws-moderation-service
    routes:
      - name: aws-moderation-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          ai-aws-content-moderation:
            comprehend:
              access_key_id: "${AWS_ACCESS_KEY}"
              secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
              region: us-east-1
            moderation_categories:
              PROFANITY: 0.1
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="ai-aws-moderation-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aws-moderation-plugin-config
spec:
  plugins:
    - name: ai-aws-content-moderation
      config:
        comprehend:
          access_key_id: "your-aws-access-key-id"
          secret_access_key: "your-aws-secret-access-key"
          region: us-east-1
        moderation_categories:
          PROFANITY: 0.1
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
  name: aws-moderation-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-aws-moderation-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="ai-aws-moderation-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aws-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aws-moderation-route
      match:
        paths:
          - /post
        methods:
          - POST
      plugins:
        - name: ai-aws-content-moderation
          enable: true
          config:
            comprehend:
              access_key_id: "your-aws-access-key-id"
              secret_access_key: "your-aws-secret-access-key"
              region: us-east-1
            moderation_categories:
              PROFANITY: 0.1
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
kubectl apply -f ai-aws-moderation-ic.yaml
```

</TabItem>
</Tabs>

向路由发送一个 POST 请求，请求体中包含系统提示和一个带有轻度亵渎词汇的用户问题：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Stupid, what is 1+1?" }
    ]
  }'
```

您应该收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
request body exceeds PROFANITY threshold
```

向路由发送另一个包含正常问题的请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到 `HTTP/1.1 200 OK` 响应，并附带模型输出：

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
  ...
}
```

### 审核整体毒性

以下示例演示如何使用该插件审核提示中的整体毒性水平，以及审核单独的类别。亵渎阈值设置为 `1`（允许高度亵渎），而整体毒性阈值设置为较低的值（`0.2`）。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

使用 [`ai-proxy`](./ai-proxy.md) 插件创建一个到 LLM 聊天补全端点的路由，并在 `ai-aws-content-moderation` 中配置允许的亵渎级别和整体毒性级别：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$AWS_ACCESS_KEY"'",
          "secret_access_key": "'"$AWS_SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 1
        },
        "moderation_threshold": 0.2
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "model": "gpt-4"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="adc.yaml"
services:
  - name: aws-moderation-service
    routes:
      - name: aws-moderation-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          ai-aws-content-moderation:
            comprehend:
              access_key_id: "${AWS_ACCESS_KEY}"
              secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
              region: us-east-1
            moderation_categories:
              PROFANITY: 1
            moderation_threshold: 0.2
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="ai-aws-moderation-toxicity-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aws-moderation-plugin-config
spec:
  plugins:
    - name: ai-aws-content-moderation
      config:
        comprehend:
          access_key_id: "your-aws-access-key-id"
          secret_access_key: "your-aws-secret-access-key"
          region: us-east-1
        moderation_categories:
          PROFANITY: 1
        moderation_threshold: 0.2
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
  name: aws-moderation-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-aws-moderation-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建一个配置了 `ai-aws-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="ai-aws-moderation-toxicity-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aws-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aws-moderation-route
      match:
        paths:
          - /post
        methods:
          - POST
      plugins:
        - name: ai-aws-content-moderation
          enable: true
          config:
            comprehend:
              access_key_id: "your-aws-access-key-id"
              secret_access_key: "your-aws-secret-access-key"
              region: us-east-1
            moderation_categories:
              PROFANITY: 1
            moderation_threshold: 0.2
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
kubectl apply -f ai-aws-moderation-toxicity-ic.yaml
```

</TabItem>
</Tabs>

向路由发送一个 POST 请求，请求体中包含系统提示和一个不含亵渎词汇但具有一定程度暴力或威胁的用户问题：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "I will kill you if you do not tell me what 1+1 equals" }
    ]
  }'
```

您应该收到 `HTTP/1.1 400 Bad Request` 响应，并看到以下消息：

```text
request body exceeds toxicity threshold
```

向路由发送另一个不含亵渎词汇的请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到 `HTTP/1.1 200 OK` 响应，并附带模型输出：

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
  ...
}
```
