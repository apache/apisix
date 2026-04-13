---
title: ai-prompt-decorator
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-decorator
description: This document contains information about the Apache APISIX ai-prompt-decorator Plugin.
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

## Description

The `ai-prompt-decorator` Plugin modifies user input prompts by prefixing and appending pre-engineered prompts to set contexts in content generation. This practice helps the model operate within desired guidelines during interactions.

## Plugin Attributes

| **Field** | **Required** | **Type** | **Description** |
| --- | --- | --- | --- |
| `prepend` | Conditionally\* | array | An array of prompt objects to be prepended. |
| `prepend.role` | True | string | Role of the message. Valid values are `system`, `user`, and `assistant`. |
| `prepend.content` | True | string | Content of the message (prompt). Minimum length: 1. |
| `append` | Conditionally\* | array | An array of prompt objects to be appended. |
| `append.role` | True | string | Role of the message. Valid values are `system`, `user`, and `assistant`. |
| `append.content` | True | string | Content of the message (prompt). Minimum length: 1. |

\* **Conditionally Required**: At least one of `prepend` or `append` must be provided.

## Examples

The following examples will be using OpenAI as the Upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api). You can optionally save the key to an environment variable as such:

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

### Prepend and Append Messages

The following example demonstrates how to configure the `ai-prompt-decorator` Plugin to prepend a system message and append a user message to the user input message. The Plugin is used together with the [ai-proxy](./ai-proxy.md) Plugin, which forwards requests to OpenAI.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route to the chat completion endpoint with pre-configured prompt decorators:

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

Create a Route with the `ai-proxy` and `ai-prompt-decorator` Plugins configured:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Create a Route with the `ai-proxy` and `ai-prompt-decorator` Plugins configured:

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

Create a Route with the `ai-proxy` and `ai-prompt-decorator` Plugins configured:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-decorator-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route specifying the model and a sample message in the request body:

```shell
curl "http://127.0.0.1:9080/openai-chat" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{ "role": "user", "content": "What is mTLS authentication?" }]
  }'
```

You should receive a response similar to the following:

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
