---
title: ai-prompt-template
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-template
description: The ai-prompt-template plugin supports pre-configuring prompt templates that only accept user inputs in designated template variables, in a fill-in-the-blank fashion.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-prompt-template" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-prompt-template` Plugin supports pre-configuring prompt templates that only accept user inputs in designated template variables, in a "fill in the blank" fashion. It simplifies access to LLM providers, such as OpenAI and Anthropic, by letting you define reusable prompt structures.

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `templates` | array | True | | | An array of template objects. |
| `templates.name` | string | True | | | Name of the template. When requesting the Route, the request should include the template name that corresponds to the configured template. |
| `templates.template` | object | True | | | Template specification. |
| `templates.template.model` | string | False | | | Name of the LLM model, such as `gpt-4` or `gpt-3.5`. See your LLM provider API documentation for more available models. |
| `templates.template.messages` | array[object] | False | | | Template message specification. |
| `templates.template.messages.role` | string | True | | [`system`, `user`, `assistant`] | Role of the message. |
| `templates.template.messages.content` | string | True | | | Content of the message (prompt). Use `{{variable_name}}` syntax to define template variables that will be filled from the request body. |

## Examples

The following examples use OpenAI as the Upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api). You can optionally save the key to an environment variable:

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Configure a Template for Open Questions in Custom Complexity

The following example demonstrates how to use the `ai-prompt-template` Plugin to configure a template that can be used to answer open questions and accepts user-specified response complexity.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route to the chat completion endpoint with pre-configured prompt templates. The [ai-proxy](./ai-proxy.md) Plugin is used to configure the OpenAI API key and model. The `ai-prompt-template` Plugin defines a template named "QnA with complexity" with two template variables: `complexity` controls the answer detail level, and `prompt` accepts the user question.

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
        },
        "options": {
          "model": "gpt-4"
        }
      },
      "ai-prompt-template": {
        "templates": [
          {
            "name": "QnA with complexity",
            "template": {
              "model": "gpt-4",
              "messages": [
                {
                  "role": "system",
                  "content": "Answer in {{complexity}}."
                },
                {
                  "role": "user",
                  "content": "Explain {{prompt}}."
                }
              ]
            }
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-prompt-template` and [ai-proxy](./ai-proxy.md) Plugins. The `ai-proxy` Plugin configures the OpenAI API key and model. The `ai-prompt-template` Plugin defines a template named "QnA with complexity" with two template variables: `complexity` controls the answer detail level, and `prompt` accepts the user question.

```yaml title="adc.yaml"
services:
  - name: prompt-template-service
    routes:
      - name: prompt-template-route
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
            options:
              model: gpt-4
          ai-prompt-template:
            templates:
              - name: "QnA with complexity"
                template:
                  model: gpt-4
                  messages:
                    - role: system
                      content: "Answer in {{complexity}}."
                    - role: user
                      content: "Explain {{prompt}}."
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Create a Route with the `ai-prompt-template` and [ai-proxy](./ai-proxy.md) Plugins. The `ai-prompt-template` Plugin defines a template named "QnA with complexity" with two template variables: `complexity` controls the answer detail level, and `prompt` accepts the user question.

```yaml title="ai-prompt-template-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-template-plugin-config
spec:
  plugins:
    - name: ai-prompt-template
      config:
        templates:
          - name: "QnA with complexity"
            template:
              model: gpt-4
              messages:
                - role: system
                  content: "Answer in {{complexity}}."
                - role: user
                  content: "Explain {{prompt}}."
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
  name: prompt-template-route
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
            name: ai-prompt-template-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

Create a Route with the `ai-prompt-template` and [ai-proxy](./ai-proxy.md) Plugins. The `ai-prompt-template` Plugin defines a template named "QnA with complexity" with two template variables: `complexity` controls the answer detail level, and `prompt` accepts the user question.

```yaml title="ai-prompt-template-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-template-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-template-route
      match:
        paths:
          - /openai-chat
        methods:
          - POST
      plugins:
        - name: ai-prompt-template
          enable: true
          config:
            templates:
              - name: "QnA with complexity"
                template:
                  model: gpt-4
                  messages:
                    - role: system
                      content: "Answer in {{complexity}}."
                    - role: user
                      content: "Explain {{prompt}}."
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

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-template-ic.yaml
```

</TabItem>
</Tabs>

The Route should now be available to respond to a variety of questions with different levels of user-specified complexity.

Send a POST request to the Route with a sample question and desired answer complexity in the request body:

```shell
curl "http://127.0.0.1:9080/openai-chat" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "QnA with complexity",
    "complexity": "brief",
    "prompt": "quick sort"
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
        "content": "Quick sort is a highly efficient sorting algorithm that uses a divide-and-conquer approach to arrange elements in a list or array in order. Here's a brief explanation:\n\n1. **Choose a Pivot**: Select an element from the list as a 'pivot'. Common methods include choosing the first element, the last element, the middle element, or a random element.\n\n2. **Partitioning**: Rearrange the elements in the list such that all elements less than the pivot are moved before it, and all elements greater than the pivot are moved after it. The pivot is now in its final position.\n\n3. **Recursively Apply**: Recursively apply the same process to the sub-lists of elements to the left and right of the pivot.\n\nThe base case of the recursion is lists of size zero or one, which are already sorted.\n\nQuick sort has an average-case time complexity of O(n log n), making it suitable for large datasets. However, its worst-case time complexity is O(n^2), which occurs when the smallest or largest element is always chosen as the pivot. This can be mitigated by using good pivot selection strategies or randomization.",
        "role": "assistant"
      }
    }
  ],
  "created": 1723194057,
  "id": "chatcmpl-9uFmTYN4tfwaXZjyOQwcp0t5law4x",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "system_fingerprint": "fp_abc28019ad",
  "usage": {
    "completion_tokens": 234,
    "prompt_tokens": 18,
    "total_tokens": 252
  }
}
```

### Configure Multiple Templates

The following example demonstrates how you can configure multiple templates on the same Route. When requesting the Route, users will be able to pass custom inputs to different templates by specifying the template name.

The example continues with the [last example](#configure-a-template-for-open-questions-in-custom-complexity). Update the Plugin with another template:

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Update the Route with an additional template named "echo" that simply echoes back the user input:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "ai-prompt-template": {
        "templates": [
          {
            "name": "QnA with complexity",
            "template": {
              "model": "gpt-4",
              "messages": [
                {
                  "role": "system",
                  "content": "Answer in {{complexity}}."
                },
                {
                  "role": "user",
                  "content": "Explain {{prompt}}."
                }
              ]
            }
          },
          {
            "name": "echo",
            "template": {
              "model": "gpt-4",
              "messages": [
                {
                  "role": "user",
                  "content": "Echo {{prompt}}."
                }
              ]
            }
          }
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Update the Route configuration with an additional template named "echo" that simply echoes back the user input:

```yaml title="adc.yaml"
services:
  - name: prompt-template-service
    routes:
      - name: prompt-template-route
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
            options:
              model: gpt-4
          ai-prompt-template:
            templates:
              - name: "QnA with complexity"
                template:
                  model: gpt-4
                  messages:
                    - role: system
                      content: "Answer in {{complexity}}."
                    - role: user
                      content: "Explain {{prompt}}."
              - name: "echo"
                template:
                  model: gpt-4
                  messages:
                    - role: user
                      content: "Echo {{prompt}}."
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Update the PluginConfig with an additional template named "echo" that simply echoes back the user input:

```yaml title="ai-prompt-template-multi-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-template-plugin-config
spec:
  plugins:
    - name: ai-prompt-template
      config:
        templates:
          - name: "QnA with complexity"
            template:
              model: gpt-4
              messages:
                - role: system
                  content: "Answer in {{complexity}}."
                - role: user
                  content: "Explain {{prompt}}."
          - name: "echo"
            template:
              model: gpt-4
              messages:
                - role: user
                  content: "Echo {{prompt}}."
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
  name: prompt-template-route
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
            name: ai-prompt-template-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

Update the ApisixRoute with an additional template named "echo" that simply echoes back the user input:

```yaml title="ai-prompt-template-multi-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-template-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-template-route
      match:
        paths:
          - /openai-chat
        methods:
          - POST
      plugins:
        - name: ai-prompt-template
          enable: true
          config:
            templates:
              - name: "QnA with complexity"
                template:
                  model: gpt-4
                  messages:
                    - role: system
                      content: "Answer in {{complexity}}."
                    - role: user
                      content: "Explain {{prompt}}."
              - name: "echo"
                template:
                  model: gpt-4
                  messages:
                    - role: user
                      content: "Echo {{prompt}}."
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

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-template-multi-ic.yaml
```

</TabItem>
</Tabs>

You should now be able to use both templates through the same Route.

Send a POST request to the Route and use the first template:

```shell
curl "http://127.0.0.1:9080/openai-chat" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "QnA with complexity",
    "complexity": "brief",
    "prompt": "quick sort"
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
        "content": "Quick sort is a highly efficient sorting algorithm that uses a divide-and-conquer approach to arrange elements in a list or array in order. Here's a brief explanation:\n\n1. **Choose a Pivot**: Select an element from the list as a 'pivot'. Common methods include choosing the first element, the last element, the middle element, or a random element.\n\n2. **Partitioning**: Rearrange the elements in the list such that all elements less than the pivot are moved before it, and all elements greater than the pivot are moved after it. The pivot is now in its final position.\n\n3. **Recursively Apply**: Recursively apply the same process to the sub-lists of elements to the left and right of the pivot.\n\nThe base case of the recursion is lists of size zero or one, which are already sorted.\n\nQuick sort has an average-case time complexity of O(n log n), making it suitable for large datasets. However, its worst-case time complexity is O(n^2), which occurs when the smallest or largest element is always chosen as the pivot. This can be mitigated by using good pivot selection strategies or randomization.",
        "role": "assistant"
      }
    }
  ],
  ...
}
```

Send a POST request to the Route and use the second template:

```shell
curl "http://127.0.0.1:9080/openai-chat" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "echo",
    "prompt": "hello APISIX"
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
        "content": "hello APISIX",
        "role": "assistant"
      }
    }
  ],
  ...
}
```
