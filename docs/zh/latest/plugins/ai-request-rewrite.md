---
title: ai-request-rewrite
keywords:
  - Apache APISIX
  - AI 网关
  - Plugin
  - ai-request-rewrite
description: ai-request-rewrite 插件在将客户端请求发送到上游服务之前，将其转发到 LLM 服务进行处理，实现 AI 驱动的脱敏、内容增强和格式转换。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-request-rewrite" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-request-rewrite` 插件在将客户端请求转发到上游服务之前，先将请求发送到 LLM 服务进行转换处理。这使得 LLM 能够对请求进行数据脱敏、内容增强或格式转换等修改。该插件支持集成 OpenAI、DeepSeek、Gemini、Vertex AI、Anthropic、OpenRouter 以及其他 OpenAI 兼容的 API。

## 插件属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `prompt` | string | 是 | | | 发送到 LLM 服务用于重写客户端请求的提示词。 |
| `provider` | string | 是 | | [openai, deepseek, azure-openai, aimlapi, gemini, vertex-ai, anthropic, openrouter, openai-compatible] | LLM 服务提供商。设置为 `aimlapi` 时，插件使用 OpenAI 兼容驱动并将请求代理到 `https://api.aimlapi.com/v1/chat/completions`。设置为 `openai-compatible` 时，插件将请求代理到 `override` 中配置的自定义端点。设置为 `azure-openai` 时，插件同样将请求代理到 `override` 中配置的自定义端点，并会额外移除用户请求中的 `model` 参数。 |
| `auth` | object | 是 | | | 身份验证配置。 |
| `auth.header` | object | 否 | | | 身份验证请求头。键必须匹配模式 `^[a-zA-Z0-9._-]+$`。`header` 和 `query` 至少需要配置其中一个。 |
| `auth.query` | object | 否 | | | 身份验证查询参数。键必须匹配模式 `^[a-zA-Z0-9._-]+$`。`header` 和 `query` 至少需要配置其中一个。 |
| `options` | object | 否 | | | 模型配置。除了 `model` 之外，还可以配置其他参数，这些参数会在请求体中转发给上游 LLM 服务。例如，使用 OpenAI 时，可以配置 `temperature`、`top_p` 和 `stream` 等参数。更多可用选项请参阅 LLM 提供商的 API 文档。 |
| `options.model` | string | 否 | | | LLM 模型名称，例如 `gpt-4` 或 `gpt-3.5`。更多可用模型请参阅 LLM 提供商的 API 文档。 |
| `override` | object | 否 | | | 覆盖设置。 |
| `override.endpoint` | string | 否 | | | LLM 提供商端点。当 `provider` 为 `openai-compatible` 时必填。 |
| `timeout` | integer | 否 | 30000 | 1 - 60000 | 请求 LLM 服务的超时时间（毫秒）。 |
| `keepalive` | boolean | 否 | true | | 是否在请求 LLM 服务时保持连接。 |
| `keepalive_timeout` | integer | 否 | 60000 | ≥ 1000 | 请求 LLM 服务的 keepalive 超时时间（毫秒）。 |
| `keepalive_pool` | integer | 否 | 30 | ≥ 1 | 连接 LLM 服务的 keepalive 连接池大小。 |
| `ssl_verify` | boolean | 否 | true | | 是否验证 LLM 服务的 SSL 证书。 |

## 工作原理

![How ai-request-rewrite works](https://static.api7.ai/uploads/2026/04/20/8J021g07_how-ai-request-rewrite-plugin-works.webp)

## 示例

以下示例演示如何为不同场景配置 `ai-request-rewrite`。

示例使用 OpenAI 作为 LLM 服务。请先获取 OpenAI [API 密钥](https://openai.com/blog/openai-api)并将其保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
```

:::note

你可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 脱敏敏感信息

以下示例演示如何使用 `ai-request-rewrite` 插件在请求到达上游服务之前脱敏敏感信息。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由并配置 `ai-request-rewrite` 插件。`provider` 设置为 `openai`，OpenAI API 密钥通过 `Authorization` 请求头传递，`prompt` 指示 LLM 识别和屏蔽敏感信息：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
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

创建带有 `ai-request-rewrite` 插件的路由：

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
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
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

发送一个包含个人敏感信息的 POST 请求到路由：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "John said his debit card number is 4111 1111 1111 1111 and SIN is 123-45-6789."
  }'
```

你应该收到类似以下的响应：

```json
{
  "args": {},
  "data": "{\"content\": \"John said his debit card number is **** **** **** 1111 and SIN is ***-**-***.\"}",
  ...,
  "json": {
    "content": "John said his debit card number is **** **** **** 1111 and SIN is ***-**-***."
  },
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.170",
  "url": "http://127.0.0.1/anything"
}
```

### 格式转换

以下示例演示如何使用 `ai-request-rewrite` 插件在请求到达上游服务之前对数据进行格式转换。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由并配置 `ai-request-rewrite` 插件。`prompt` 指示 LLM 将自然语言查询转换为结构化 JSON：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Convert natural language queries into structured JSON format with intent and extracted parameters."
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

创建带有 `ai-request-rewrite` 插件的路由：

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
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
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

发送一个 POST 请求到路由：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Book a flight from NYC to LA on April 10, 2022."
  }'
```

你应该收到类似以下的响应：

```json
{
  "args": {},
  "data": "{\n  \"intent\": \"BookFlight\",\n  \"parameters\": {\n    \"origin\": \"NYC\",\n    \"destination\": \"LA\",\n    \"date\": \"2022-04-10\"\n  }\n}",
  ...,
  "json": {
    "intent": "BookFlight",
    "parameters": {
      "date": "2022-04-10",
      "destination": "LA",
      "origin": "NYC"
    }
  },
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.167",
  "url": "http://127.0.0.1/anything"
}
```

### 信息摘要

以下示例演示如何使用 `ai-request-rewrite` 插件在请求到达上游服务之前对信息进行摘要。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由并配置 `ai-request-rewrite` 插件。`prompt` 指示 LLM 在保留关键细节的同时对冗长输入进行摘要：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
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

创建带有 `ai-request-rewrite` 插件的路由：

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
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
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

发送一个包含冗长内容的 POST 请求到路由：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Hey! So, I'\''m planning a trip to Japan next spring for about three weeks, and I want to visit Tokyo, Kyoto, and Osaka, but I'\''m not sure how to split my time between them. I really love history and cultural sites, so temples and shrines are a must. I'\''m also a big foodie, especially into ramen and sushi, so I'\''d love recommendations on the best spots. I prefer quieter areas for accommodation, but I don'\''t mind traveling into busy areas for sightseeing. Oh, and I'\''d also like to do a day trip somewhere outside these cities—maybe Hakone or Nara? I heard the cherry blossoms might still be in bloom in early April, so I'\''d love to catch them if possible. Also, what'\''s the best way to get around—should I get a JR Pass, or would individual tickets be better? Thanks!"
  }'
```

你应该收到类似以下的响应：

```json
{
  "args": {},
  "data": "The individual is planning a three-week trip to Japan in the spring, looking to visit Tokyo, Kyoto, and Osaka. They are interested in history, culture, temples, and shrines. They love ramen and sushi, so are seeking food recommendations. Accommodation should be in quieter areas, but they are open to busy sites for sightseeing. Along with these cities, they plan to make a day trip to either Hakone or Nara, hoping to see the cherry blossoms in early April. The best transport method between buying the JR Pass or individual tickets is also a query.",
  ...,
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.171",
  "url": "http://127.0.0.1/anything"
}
```

### 向 OpenAI 兼容的 LLM 发送请求

以下示例演示如何通过将 `provider` 设置为 `openai-compatible` 并在 `override.endpoint` 中配置自定义端点，来使用 `ai-request-rewrite` 插件与 OpenAI 兼容的 LLM 提供商。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由并配置 `ai-request-rewrite` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged.",
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "Authorization": "Bearer <your-api-key>"
          }
        },
        "options": {
          "model": "qwen-plus",
          "max_tokens": 1024,
          "temperature": 1
        },
        "override": {
          "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
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

创建带有 `ai-request-rewrite` 插件的路由：

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        plugins:
          ai-request-rewrite:
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
            provider: openai-compatible
            auth:
              header:
                Authorization: "Bearer <your-api-key>"
            options:
              model: qwen-plus
              max_tokens: 1024
              temperature: 1
            override:
              endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
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
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
        provider: openai-compatible
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: qwen-plus
          max_tokens: 1024
          temperature: 1
        override:
          endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
            provider: openai-compatible
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: qwen-plus
              max_tokens: 1024
              temperature: 1
            override:
              endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>
