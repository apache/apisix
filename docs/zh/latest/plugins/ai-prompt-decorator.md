---
title: ai-prompt-decorator
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-decorator
description: 本文档包含有关 Apache APISIX ai-prompt-decorator 插件的信息。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-prompt-decorator" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-prompt-decorator` 插件通过在用户输入提示前后添加预设提示来修改用户输入，以在内容生成中设定上下文。这种做法有助于模型在交互过程中按照预期的指导方针运行。

## 插件属性

| **字段** | **必选项** | **类型** | **描述** |
| --- | --- | --- | --- |
| `prepend` | 条件必选\* | Array | 要前置的提示对象数组。 |
| `prepend.role` | 是 | String | 消息的角色。可选值为 `system`、`user` 和 `assistant`。 |
| `prepend.content` | 是 | String | 消息的内容（提示）。最小长度：1。 |
| `append` | 条件必选\* | Array | 要追加的提示对象数组。 |
| `append.role` | 是 | String | 消息的角色。可选值为 `system`、`user` 和 `assistant`。 |
| `append.content` | 是 | String | 消息的内容（提示）。最小长度：1。 |

\* **条件必选**：必须提供 `prepend` 或 `append` 中的至少一个。

## 示例

以下示例将使用 OpenAI 作为上游服务提供商。在开始之前，请创建一个 [OpenAI 账户](https://openai.com) 和一个 [API 密钥](https://openai.com/blog/openai-api)。你可以选择将密钥保存到环境变量中：

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

如果你使用的是其他 LLM 提供商，请参阅该提供商的文档以获取 API 密钥。

### 前置和追加消息

以下示例演示了如何配置 `ai-prompt-decorator` 插件，在用户输入消息前添加一条系统消息，并在其后追加一条用户消息。该插件与 [ai-proxy](./ai-proxy.md) 插件配合使用，将请求转发到 OpenAI。

:::note
你可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建一个路由到聊天补全端点，并配置预设提示装饰器：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/openai-chat",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        }
      },
      "ai-prompt-decorator": {
        "prepend":[
          {
            "role": "system",
            "content": "Answer briefly and conceptually."
          }
        ],
        "append":[
          {
            "role": "user",
            "content": "End the answer with a simple analogy."
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建一个配置了 `ai-proxy` 和 `ai-prompt-decorator` 插件的路由：

```yaml title="adc.yaml"
services:
  - name: prompt-decorator-service
    routes:
      - name: prompt-decorator-route
        uris:
          - /openai-chat
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
          ai-prompt-decorator:
            prepend:
              - role: system
                content: "Answer briefly and conceptually."
            append:
              - role: user
                content: "End the answer with a simple analogy."
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建一个配置了 `ai-proxy` 和 `ai-prompt-decorator` 插件的路由：

```yaml title="ai-prompt-decorator-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-decorator-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
    - name: ai-prompt-decorator
      config:
        prepend:
          - role: system
            content: "Answer briefly and conceptually."
        append:
          - role: user
            content: "End the answer with a simple analogy."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prompt-decorator-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /openai-chat
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-prompt-decorator-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建一个配置了 `ai-proxy` 和 `ai-prompt-decorator` 插件的路由：

```yaml title="ai-prompt-decorator-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-decorator-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-decorator-route
      match:
        paths:
          - /openai-chat
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
        - name: ai-prompt-decorator
          enable: true
          config:
            prepend:
              - role: system
                content: "Answer briefly and conceptually."
            append:
              - role: user
                content: "End the answer with a simple analogy."
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-prompt-decorator-ic.yaml
```

</TabItem>
</Tabs>

向路由发送 POST 请求，在请求体中指定模型和示例消息：

```shell
curl "http://127.0.0.1:9080/openai-chat" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{ "role": "user", "content": "What is mTLS authentication?" }]
  }'
```

你应该会收到类似以下的响应：

```json
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": {
        "content": "Mutual TLS (mTLS) authentication is a security protocol that ensures both the client and server authenticate each other's identity before establishing a connection. This mutual authentication is achieved through the exchange and verification of digital certificates, which are cryptographically signed credentials proving each party's identity. In contrast to standard TLS, where only the server is authenticated, mTLS adds an additional layer of trust by verifying the client as well, providing enhanced security for sensitive communications.\n\nThink of mTLS as a secret handshake between two friends meeting at a club. Both must know the handshake to get in, ensuring they recognize and trust each other before entering.",
        "role": "assistant"
      }
    }
  ],
  "created": 1723193502,
  "id": "chatcmpl-9uFdWDlwKif6biCt9DpG0xgedEamg",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "system_fingerprint": "fp_abc28019ad",
  "usage": {
    "completion_tokens": 124,
    "prompt_tokens": 31,
    "total_tokens": 155
  }
}
```
