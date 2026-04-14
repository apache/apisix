---
title: ai-proxy
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-proxy
  - AI
  - LLM
description: ai-proxy 插件通过将插件配置转换为所需的请求格式，简化了对 LLM 和嵌入模型提供商的访问，支持 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容的 API。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-proxy" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-proxy` 插件通过将插件配置转换为指定的请求格式，简化了对 LLM 和嵌入模型的访问。它支持与 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容的 API 集成。

此外，该插件还支持在访问日志中记录 LLM 请求信息，如令牌使用量、模型、首次响应时间等。

## 请求格式

| 名称               | 类型   | 必选项 | 描述                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | 是      | 消息对象数组。                        |
| `messages.role`    | String | 是      | 消息的角色（`system`、`user`、`assistant`）。|
| `messages.content` | String | 是      | 消息的内容。                             |

## 属性

| 名称               | 类型    | 必选项 | 默认值 | 有效值                              | 描述 |
|--------------------|--------|----------|---------|------------------------------------------|-------------|
| provider          | string  | 是     |         | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, openai-compatible] | LLM 服务提供商。当设置为 `openai` 时，插件将代理请求到 `https://api.openai.com/chat/completions`。当设置为 `deepseek` 时，插件将代理请求到 `https://api.deepseek.com/chat/completions`。当设置为 `aimlapi` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://api.aimlapi.com/v1/chat/completions`。当设置为 `anthropic` 时，插件将代理请求到 `https://api.anthropic.com/v1/chat/completions`。当设置为 `openrouter` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://openrouter.ai/api/v1/chat/completions`。当设置为 `gemini` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`。当设置为 `vertex-ai` 时，插件默认将请求代理到 `https://aiplatform.googleapis.com`，需要配置 `provider_conf` 或 `override`。当设置为 `openai-compatible` 时，插件将代理请求到在 `override` 中配置的自定义端点。当设置为 `azure-openai` 时，插件同样将请求代理到 `override` 中配置的自定义端点，并会额外移除用户请求中的 `model` 参数。 |
| provider_conf      | object  | 否    |         |                                          | 特定提供商的配置。当 `provider` 设置为 `vertex-ai` 且未配置 `override` 时必需。 |
| provider_conf.project_id | string | 是 |       |                                          | Google Cloud 项目 ID。  |
| provider_conf.region | string | 是   |         |                                          | Google Cloud 区域。  |
| auth             | object  | 是     |         |                                          | 身份验证配置。 |
| auth.header      | object  | 否    |         |                                          | 身份验证标头。必须配置 `header` 或 `query` 中的至少一个。 |
| auth.query       | object  | 否    |         |                                          | 身份验证查询参数。必须配置 `header` 或 `query` 中的至少一个。 |
| auth.gcp         | object  | 否    |         |                                          | Google Cloud Platform (GCP) 身份验证配置。 |
| auth.gcp.service_account_json | string | 否 |  |                                          | GCP 服务账号 JSON 文件内容。也可以通过设置 `GCP_SERVICE_ACCOUNT` 环境变量来配置。 |
| auth.gcp.max_ttl | integer | 否    |         | ≥ 1                              | GCP 访问令牌缓存的最大 TTL（秒）。 |
| auth.gcp.expire_early_secs | integer | 否 | 60 | ≥ 0                              | 在访问令牌实际过期之前提前过期的秒数，以避免边缘情况。 |
| options         | object  | 否    |         |                                          | 模型配置。除了 `model` 之外，您还可以配置其他参数，它们将在请求体中转发到上游 LLM 服务。例如，如果您使用 OpenAI，可以配置其他参数，如 `temperature`、`top_p` 和 `stream`。有关更多可用选项，请参阅您的 LLM 提供商的 API 文档。  |
| options.model   | string  | 否    |         |                                          | LLM 模型的名称，如 `gpt-4` 或 `gpt-3.5`。请参阅 LLM 提供商的 API 文档以了解可用模型。 |
| override        | object  | 否    |         |                                          | 覆盖设置。 |
| override.endpoint | string | 否    |         |                                          | 自定义 LLM 提供商端点，当 `provider` 为 `openai-compatible` 时必需。 |
| logging        | object  | 否    |         |                                          | 日志配置。 |
| logging.summaries | boolean | 否 | false |                                          | 如果为 true，记录请求 LLM 模型、持续时间、请求和响应令牌。 |
| logging.payloads  | boolean | 否 | false |                                          | 如果为 true，记录请求和响应负载。 |
| timeout        | integer | 否    | 30000    | 1 - 600000                               | 请求 LLM 服务时的请求超时时间（毫秒）。 |
| keepalive      | boolean | 否    | true   |                                          | 如果为 true，在请求 LLM 服务时保持连接活跃。 |
| keepalive_timeout | integer | 否 | 60000  | ≥ 1000                                   | 连接到 LLM 服务时的保活超时时间（毫秒）。 |
| keepalive_pool | integer | 否    | 30       | ≥ 1                                      | LLM 服务连接的保活池大小。 |
| ssl_verify     | boolean | 否    | true   |                                          | 如果为 true，验证 LLM 服务的证书。 |

## 示例

以下示例演示了如何为不同场景配置 `ai-proxy`。

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 代理到 OpenAI

以下示例演示了如何在 `ai-proxy` 插件中配置 API 密钥、模型和其他参数，并在 Route 上配置插件以将用户提示代理到 OpenAI。

获取 OpenAI [API 密钥](https://openai.com/blog/openai-api)并保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
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
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route：

```yaml title="adc.yaml"
services:
  - name: openai-service
    routes:
      - name: openai-route
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

```yaml title="ai-proxy-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
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
  name: openai-route
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
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ai-proxy-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: openai-route
spec:
  ingressClassName: apisix
  http:
    - name: openai-route
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
            model: gpt-4
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-proxy-ic.yaml
```

</TabItem>

</Tabs>

向 Route 发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "Host: api.openai.com" \
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
  ...
}
```

### 代理到 DeepSeek

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到 DeepSeek。

获取 DeepSeek API 密钥并保存到环境变量：

```shell
export DEEPSEEK_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "deepseek",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
          }
        },
        "options": {
          "model": "deepseek-chat"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route：

```yaml title="adc.yaml"
services:
  - name: deepseek-service
    routes:
      - name: deepseek-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: deepseek
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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="deepseek-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: deepseek
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
  name: deepseek-route
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
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="deepseek-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: deepseek-route
spec:
  ingressClassName: apisix
  http:
    - name: deepseek-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: deepseek
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: deepseek-chat
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f deepseek-ic.yaml
```

</TabItem>

</Tabs>

向 Route 发送 POST 请求，在请求体中包含示例问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are an AI assistant that helps people find information."
      },
      {
        "role": "user",
        "content": "Write me a 50-word introduction for Apache APISIX."
      }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a dynamic, real-time, high-performance API gateway and cloud-native platform. It provides rich traffic management features like load balancing, dynamic upstream, canary release, circuit breaking, authentication, observability, and more. Designed for microservices and serverless architectures, APISIX ensures scalability, security, and seamless integration with modern DevOps workflows."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

### 代理到 Azure OpenAI

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到其他 LLM 服务，如 Azure OpenAI。

获取 Azure OpenAI API 密钥并保存到环境变量：

```shell
export AZ_OPENAI_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件，将 `provider` 设置为 `azure-openai`，在 `api-key` 标头中附加 Azure OpenAI API 密钥，并指定 Azure OpenAI 端点：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "azure-openai",
        "auth": {
          "header": {
            "api-key": "'"$AZ_OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "override": {
          "endpoint": "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route，将 `provider` 设置为 `azure-openai`，在 `api-key` 标头中附加 Azure OpenAI API 密钥，并指定 Azure OpenAI 端点：

```yaml title="adc.yaml"
services:
  - name: azure-openai-service
    routes:
      - name: azure-openai-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: azure-openai
            auth:
              header:
                api-key: "${AZ_OPENAI_API_KEY}"
            options:
              model: gpt-4
            override:
              endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
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

```yaml title="azure-openai-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: azure-openai
        auth:
          header:
            api-key: "your-api-key"
        options:
          model: gpt-4
        override:
          endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: azure-openai-route
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
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="azure-openai-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: azure-openai-route
spec:
  ingressClassName: apisix
  http:
    - name: azure-openai-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: azure-openai
          auth:
            header:
              api-key: "your-api-key"
          options:
            model: gpt-4
          override:
            endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f azure-openai-ic.yaml
```

</TabItem>

</Tabs>

向 Route 发送 POST 请求，在请求体中包含示例问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are an AI assistant that helps people find information."
      },
      {
        "role": "user",
        "content": "Write me a 50-word introduction for Apache APISIX."
      }
    ],
    "max_tokens": 800,
    "temperature": 0.7,
    "frequency_penalty": 0,
    "presence_penalty": 0,
    "top_p": 0.95,
    "stop": null
  }'
```

您应该收到类似以下的响应：

```json
{
  "choices": [
    {
      ...,
      "message": {
        "content": "Apache APISIX is a modern, cloud-native API gateway built to handle high-performance and low-latency use cases. It offers a wide range of features, including load balancing, rate limiting, authentication, and dynamic routing, making it an ideal choice for microservices and cloud-native architectures.",
        "role": "assistant"
      }
    }
  ],
  ...
}
```

### 代理到 OpenAI 嵌入模型

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到嵌入模型。此示例将使用 OpenAI 嵌入模型端点。

获取 OpenAI [API 密钥](https://openai.com/blog/openai-api)并保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件，将 `provider` 设置为 `openai`，指定嵌入模型名称，添加 `encoding_format` 参数以配置返回的嵌入向量为浮点数列表，并使用 `override` 将默认端点覆盖为 [嵌入 API 端点](https://platform.openai.com/docs/api-reference/embeddings)：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/embeddings",
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
          "model": "text-embedding-3-small",
          "encoding_format": "float"
        },
        "override": {
          "endpoint": "https://api.openai.com/v1/embeddings"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route，将 `provider` 设置为 `openai`，指定嵌入模型名称，添加 `encoding_format` 参数，并使用 `override` 将默认端点覆盖为 [嵌入 API 端点](https://platform.openai.com/docs/api-reference/embeddings)：

```yaml title="adc.yaml"
services:
  - name: openai-embeddings-service
    routes:
      - name: openai-embeddings-route
        uris:
          - /embeddings
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: text-embedding-3-small
              encoding_format: float
            override:
              endpoint: "https://api.openai.com/v1/embeddings"
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

```yaml title="openai-embeddings-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: text-embedding-3-small
          encoding_format: float
        override:
          endpoint: "https://api.openai.com/v1/embeddings"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: openai-embeddings-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /embeddings
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="openai-embeddings-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: openai-embeddings-route
spec:
  ingressClassName: apisix
  http:
    - name: openai-embeddings-route
      match:
        paths:
          - /embeddings
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
            model: text-embedding-3-small
            encoding_format: float
          override:
            endpoint: "https://api.openai.com/v1/embeddings"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f openai-embeddings-ic.yaml
```

</TabItem>

</Tabs>

向 Route 发送 POST 请求，包含输入字符串：

```shell
curl "http://127.0.0.1:9080/embeddings" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "input": "hello world"
  }'
```

您应该收到类似以下的响应：

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [
        -0.0067144386,
        -0.039197803,
        0.034177095,
        0.028763203,
        -0.024785956,
        -0.04201061,
        ...
      ],
    }
  ],
  "model": "text-embedding-3-small",
  "usage": {
    "prompt_tokens": 2,
    "total_tokens": 2
  }
}
```

### 代理到 Anthropic

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到 Anthropic 的 Claude API 进行聊天补全。

获取 Anthropic [API 密钥](https://console.anthropic.com/settings/keys)并保存到环境变量：

```shell
export ANTHROPIC_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件，将 `provider` 设置为 `anthropic`，并在 `x-api-key` 标头中附加 Anthropic API 密钥：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-anthropic-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "anthropic",
        "auth": {
          "header": {
            "x-api-key": "'"$ANTHROPIC_API_KEY"'"
          }
        },
        "options": {
          "model": "claude-sonnet-4-20250514"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route，将 `provider` 设置为 `anthropic`，并在 `x-api-key` 标头中附加 Anthropic API 密钥：

```yaml title="adc.yaml"
services:
  - name: anthropic-service
    routes:
      - name: anthropic-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: anthropic
            auth:
              header:
                x-api-key: "${ANTHROPIC_API_KEY}"
            options:
              model: claude-sonnet-4-20250514
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

```yaml title="anthropic-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: anthropic
        auth:
          header:
            x-api-key: "your-api-key"
        options:
          model: claude-sonnet-4-20250514
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: anthropic-route
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
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="anthropic-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: anthropic-route
spec:
  ingressClassName: apisix
  http:
    - name: anthropic-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: anthropic
          auth:
            header:
              x-api-key: "your-api-key"
          options:
            model: claude-sonnet-4-20250514
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f anthropic-ic.yaml
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
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "1+1 equals 2."
    }
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 19,
    "output_tokens": 11
  }
}
```

### 将 Anthropic 请求转换为 OpenAI 兼容后端

以下示例演示了 `ai-proxy` 插件如何接受 Anthropic Messages API 格式的请求，并自动将其转换为 OpenAI 兼容格式，然后转发到任何 OpenAI 兼容后端（如 OpenAI、DeepSeek 或其他兼容服务）。当客户端应用程序发送 Anthropic 格式的请求但您希望使用不同的 LLM 后端时，这非常有用。

当 Route URI 设置为 `/v1/messages`（Anthropic Messages API 端点）时，协议转换会自动触发。插件会将 Anthropic 格式的请求转换为 OpenAI 兼容格式，并将响应转换回 Anthropic 格式。

获取您选择的 OpenAI 兼容后端服务的 API 密钥并保存到环境变量。此示例使用 OpenAI：

```shell
export BACKEND_API_KEY=<your-api-key>
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

创建 Route 并配置 `ai-proxy` 插件。将 URI 设置为 `/v1/messages` 以触发自动 Anthropic 协议转换，后端提供商可以是任何 OpenAI 兼容的提供商：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-anthropic-convert-route",
    "uri": "/v1/messages",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$BACKEND_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 插件配置的 Route。将 URI 设置为 `/v1/messages` 以触发自动 Anthropic 协议转换，后端提供商可以是任何 OpenAI 兼容的提供商：

```yaml title="adc.yaml"
services:
  - name: anthropic-convert-service
    routes:
      - name: anthropic-convert-route
        uris:
          - /v1/messages
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${BACKEND_API_KEY}"
            options:
              model: gpt-4
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

```yaml title="anthropic-convert-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
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
  name: anthropic-convert-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /v1/messages
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="anthropic-convert-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: anthropic-convert-route
spec:
  ingressClassName: apisix
  http:
    - name: anthropic-convert-route
      match:
        paths:
          - /v1/messages
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
            model: gpt-4
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f anthropic-convert-ic.yaml
```

</TabItem>

</Tabs>

以 Anthropic Messages API 格式向 Route 发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/v1/messages" -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${BACKEND_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "gpt-4",
    "max_tokens": 1024,
    "messages": [
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

尽管请求以 Anthropic 格式发送，但它将自动转换为 OpenAI 格式并转发到后端。响应将转换回 Anthropic 格式：

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "1+1 equals 2."
    }
  ],
  "model": "gpt-4",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 12,
    "output_tokens": 8
  }
}
```

该插件支持 Anthropic Messages API 的所有功能，包括流式传输 (SSE)、系统提示和工具使用（函数调用）。协议转换透明地处理 Anthropic 和 OpenAI 格式之间的双向映射。

### 使用请求体参数代理到选定模型

以下示例演示了如何基于用户请求中指定的模型参数，在同一 URI 上将请求代理到不同的模型。您可以使用 `post_arg.*` 变量来获取请求体参数的值。

此示例将使用 OpenAI 和 DeepSeek 作为示例 LLM 服务。获取 OpenAI 和 DeepSeek API 密钥并保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
export DEEPSEEK_API_KEY=<your-api-key>
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

创建一个到 OpenAI API 的 Route，使用 `vars` 匹配请求体参数 `model` 为 `openai` 的请求：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-openai-route",
    "uri": "/anything",
    "methods": ["POST"],
    "vars": [[ "post_arg.model", "==", "openai" ]],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    }
  }'
```

创建另一个到 DeepSeek API 的 Route `/anything`，使用 `vars` 匹配请求体参数 `model` 为 `deepseek` 的请求：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-deepseek-route",
    "uri": "/anything",
    "methods": ["POST"],
    "vars": [[ "post_arg.model", "==", "deepseek" ]],
    "plugins": {
      "ai-proxy": {
        "provider": "deepseek",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
          }
        },
        "options": {
          "model": "deepseek-chat"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建两个包含 `ai-proxy` 插件的 Route，分别配置不同的提供商。使用 `vars` 匹配请求体参数 `model` 来决定路由到哪个提供商：

```yaml title="adc.yaml"
services:
  - name: multi-model-service
    routes:
      - name: openai-route
        uris:
          - /anything
        methods:
          - POST
        vars:
          - - post_arg.model
            - ==
            - openai
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
      - name: deepseek-route
        uris:
          - /anything
        methods:
          - POST
        vars:
          - - post_arg.model
            - ==
            - deepseek
        plugins:
          ai-proxy:
            provider: deepseek
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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

:::info

HTTPRoute 不支持请求体参数匹配。支持的匹配机制为 `path`、`method`、`headers` 和 `queryParams`。此示例无法使用 Gateway API 完成。

:::

</TabItem>

<TabItem value="apisix-crd">

:::info

ApisixRoute 当前不支持请求体参数匹配。支持的匹配机制基于 `Header`、`Query` 或 `Path`。此示例无法使用 APISIX CRD 完成。

:::

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向 Route 发送 POST 请求，将 `model` 设置为 `openai`：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai",
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
  ...
}
```

向 Route 发送 POST 请求，将 `model` 设置为 `deepseek`：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek",
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
  ...
}
```

您还可以配置 `post_arg.*` 来获取嵌套的请求体参数。例如，如果请求格式为：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": {
      "name": "openai"
    },
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您可以将 Route 上的 `vars` 配置为 `[[ "post_arg.model.name", "==", "openai" ]]`。

### 发送请求日志到日志记录器

以下示例演示了如何记录请求和响应信息（包括 LLM 模型、令牌和负载），并将其推送到日志记录器。在开始之前，您应该先设置一个日志记录器，例如 Kafka。有关更多信息，请参阅 [`kafka-logger`](./kafka-logger.md)。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建到 LLM 服务的 Route，并配置日志详情。将 `logging.summaries` 设置为 `true` 以记录请求 LLM 模型、持续时间、请求和响应令牌，将 `logging.payloads` 设置为 `true` 以记录请求和响应负载。同时配置 `kafka-logger` 插件，设置 Kafka 地址、主题、密钥，并将 `batch_max_size` 设置为 `1` 以立即发送日志条目：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-openai-route",
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
          "model": "gpt-4"
        },
        "logging": {
          "summaries": true,
          "payloads": true
        }
      },
      "kafka-logger": {
        "brokers": [
          {
            "host": "127.0.0.1",
            "port": 9092
          }
        ],
        "kafka_topic": "test2",
        "key": "key1",
        "batch_max_size": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建包含 `ai-proxy` 和 `kafka-logger` 插件的 Route。将 `logging.summaries` 设置为 `true` 以记录请求 LLM 模型、持续时间、请求和响应令牌，将 `logging.payloads` 设置为 `true` 以记录请求和响应负载：

```yaml title="adc.yaml"
services:
  - name: logging-service
    routes:
      - name: logging-route
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
            logging:
              summaries: true
              payloads: true
          kafka-logger:
            brokers:
              - host: 127.0.0.1
                port: 9092
            kafka_topic: test2
            key: key1
            batch_max_size: 1
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

```yaml title="logging-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-logging-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        logging:
          summaries: true
          payloads: true
    - name: kafka-logger
      config:
        brokers:
          - host: kafka.aic.svc.cluster.local
            port: 9092
        kafka_topic: test2
        key: key1
        batch_max_size: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: logging-route
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
            name: ai-proxy-logging-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="logging-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: logging-route
spec:
  ingressClassName: apisix
  http:
    - name: logging-route
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
            model: gpt-4
          logging:
            summaries: true
            payloads: true
      - name: kafka-logger
        enable: true
        config:
          brokers:
            - host: kafka.aic.svc.cluster.local
              port: 9092
          kafka_topic: test2
          key: key1
          batch_max_size: 1
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f logging-ic.yaml
```

</TabItem>

</Tabs>

向 Route 发送 POST 请求：

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
  ...
}
```

在 Kafka 主题中，您应该还会看到与请求对应的日志条目，其中包含 LLM 摘要和请求/响应负载。

### 在访问日志中包含 LLM 信息

以下示例演示了如何在网关的访问日志中记录 LLM 请求相关信息，以改进分析和审计。以下变量可用：

* `request_llm_model`：请求中指定的 LLM 模型名称。
* `apisix_upstream_response_time`：APISIX 向上游服务发送请求并接收完整响应所花费的时间
* `request_type`：请求类型，值可能是 `traditional_http`、`ai_chat` 或 `ai_stream`。
* `llm_time_to_first_token`：从发送请求到从 LLM 服务接收第一个令牌的持续时间（毫秒）。
* `llm_model`：LLM 模型。
* `llm_prompt_tokens`：提示中的令牌数量。
* `llm_completion_tokens`：提示中的聊天完成令牌数量。

在配置文件中更新访问日志格式以包含其他 LLM 相关变量：

```yaml title="conf/config.yaml"
nginx_config:
  http:
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host \"$request_line\" $status $body_bytes_sent $request_time \"$http_referer\" \"$http_user_agent\" $upstream_addr $upstream_status $apisix_upstream_response_time \"$upstream_scheme://$upstream_host$upstream_uri\" \"$apisix_request_id\" \"$request_type\" \"$llm_time_to_first_token\" \"$llm_model\" \"$request_llm_model\"  \"$llm_prompt_tokens\" \"$llm_completion_tokens\""
```

重新加载 APISIX 以使配置更改生效。

现在，如果您创建 Route 并按照[代理到 OpenAI 示例](#代理到-openai)发送请求，您应该收到类似以下的响应：

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
        "refusal": null,
        "annotations": []
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
    ...
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

在网关的访问日志中，您应该看到类似以下的日志条目：

```text
192.168.215.1 - - [21/Mar/2025:04:28:03 +0000] api.openai.com "POST /anything HTTP/1.1" 200 804 2.858 "-" "curl/8.6.0" - - - 5765 "http://api.openai.com" "5c5e0b95f8d303cb81e4dc456a4b12d9" "ai_chat" "2858" "gpt-4" "gpt-4" "23" "8"
```

访问日志条目显示请求类型为 `ai_chat`，Apisix 上游响应时间为 `5765` 毫秒，首次令牌时间为 `2858` 毫秒，请求的 LLM 模型为 `gpt-4`。LLM 模型为 `gpt-4`，提示令牌使用量为 `23`，完成令牌使用量为 `8`。
