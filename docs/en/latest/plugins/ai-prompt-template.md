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

## Description

The `ai-prompt-template` Plugin simplifies access to LLM providers, such as OpenAI and Anthropic, and their models. It pre-configures prompt templates that only accept user inputs in designated template variables, in a "fill in the blank" fashion.

## Plugin Attributes

| **Field** | **Required** | **Type** | **Description** |
| :--- | :--- | :--- | :--- |
| `templates` | Yes | Array | An array of template objects. |
| `templates.name` | Yes | String | Name of the template. When requesting the route, the request should include the template name that corresponds to the configured template. |
| `templates.template` | Yes | Object | Template specification. |
| `templates.template.model` | Yes | String | Name of the AI Model, such as `gpt-4` or `gpt-3.5`. See your LLM provider API documentation for more available models. |
| `templates.template.messages` | Yes | Array | Template message specification. |
| `templates.template.messages.role` | Yes | String | Role of the message, such as `system`, `user`, or `assistant`. |
| `templates.template.messages.content` | Yes | String | Content of the message (prompt). |

## Examples

The following examples will be using OpenAI as the Upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api). You can optionally save the key to an environment variable as such:

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

### Configure a Template for Open Questions in Custom Complexity

The following example demonstrates how to use the `ai-prompt-template` Plugin to configure a template which can be used to answer open questions and accepts user-specified response complexity.

Create a Route to the chat completion endpoint with pre-configured prompt templates as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/v1/chat/completions",
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

Send a POST request to the Route with a sample question and desired answer complexity in the request body.

Now send a request:

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
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
        "content": "Quick sort is a highly efficient sorting algorithm that uses a divide-and-conquer approach to arrange elements in a list or array in order. Here’s a brief explanation:\n\n1. **Choose a Pivot**: Select an element from the list as a 'pivot'. Common methods include choosing the first element, the last element, the middle element, or a random element.\n\n2. **Partitioning**: Rearrange the elements in the list such that all elements less than the pivot are moved before it, and all elements greater than the pivot are moved after it. The pivot is now in its final position.\n\n3. **Recursively Apply**: Recursively apply the same process to the sub-lists of elements to the left and right of the pivot.\n\nThe base case of the recursion is lists of size zero or one, which are already sorted.\n\nQuick sort has an average-case time complexity of O(n log n), making it suitable for large datasets. However, its worst-case time complexity is O(n^2), which occurs when the smallest or largest element is always chosen as the pivot. This can be mitigated by using good pivot selection strategies or randomization.",
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

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/v1/chat/completions",
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
                  "role": "system",
                  "content": "You are an echo bot. You must repeat exactly what the user says without any changes or additional text."
                },
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

You should now be able to use both templates through the same Route.

Send a POST request to the Route and use the first template:

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
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
        "content": "Quick sort is a highly efficient sorting algorithm that uses a divide-and-conquer approach to arrange elements in a list or array in order. Here’s a brief explanation:\n\n1. **Choose a Pivot**: Select an element from the list as a 'pivot'. Common methods include choosing the first element, the last element, the middle element, or a random element.\n\n2. **Partitioning**: Rearrange the elements in the list such that all elements less than the pivot are moved before it, and all elements greater than the pivot are moved after it. The pivot is now in its final position.\n\n3. **Recursively Apply**: Recursively apply the same process to the sub-lists of elements to the left and right of the pivot.\n\nThe base case of the recursion is lists of size zero or one, which are already sorted.\n\nQuick sort has an average-case time complexity of O(n log n), making it suitable for large datasets. However, its worst-case time complexity is O(n^2), which occurs when the smallest or largest element is always chosen as the pivot. This can be mitigated by using good pivot selection strategies or randomization.",
        "role": "assistant"
      }
    }
  ],
  ...
}
```

Send a POST request to the Route and use the second template:

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
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
