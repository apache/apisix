---
title: ai-prompt-template
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-template
description: ai-prompt-template 插件支持预先配置提示词模板，这些模板仅接受用户在指定的模板变量中输入，采用填空的方式。
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

## 描述

`ai-prompt-template` 插件简化了对 OpenAI、Anthropic 等大语言模型提供商及其模型的访问。它预先配置提示词模板，这些模板仅接受用户在指定的模板变量中输入，采用“填空”的方式。

## 插件属性

| **字段** | **是否必填** | **类型** | **描述** |
| :--- | :--- | :--- | :--- |
| `templates` | 是 | Array | 模板对象数组。 |
| `templates.name` | 是 | String | 模板的名称。在请求路由时，请求中应包含与所配置模板相对应的模板名称。 |
| `templates.template` | 是 | Object | 模板规范。 |
| `templates.template.model` | 是 | String | AI 模型的名称，例如 `gpt-4` 或 `gpt-3.5`。更多可用模型请参阅 LLM 提供商的 API 文档。 |
| `templates.template.messages` | 是 | Array | 模板消息规范。 |
| `templates.template.messages.role` | 是 | String | 消息的角色，例如 `system`、`user` 或 `assistant`。 |
| `templates.template.messages.content` | 是 | String | 消息（提示词）的内容。 |

## 使用示例

以下示例将使用 OpenAI 作为上游服务提供商。开始之前，请先创建一个 OpenAI 账户和一个 API 密钥。你可以选择将密钥保存到环境变量中，如下所示：

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>   # 替换为你的 API 密钥
```

如果你正在使用其他 LLM 提供商，请参阅该提供商的文档以获取 API 密钥。

### 为自定义复杂度的开放式问题配置模板

以下示例演示了如何使用 `ai-prompt-template` 插件配置一个模板，该模板可用于回答开放式问题并接受用户指定的回答复杂度。

创建一个指向聊天补全端点的路由，并配置预定义的提示词模板：

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

向该路由发送一个 POST 请求，在请求体中包含示例问题和期望的回答复杂度。

发送请求：

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "QnA with complexity",
    "complexity": "brief",
    "prompt": "quick sort"
  }'
```

你应该会收到类似于以下的响应：

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

### 配置多个模板

以下示例演示了如何在同一条路由上配置多个模板。请求该路由时，用户将能够通过指定模板名称向不同模板传递自定义输入。

该示例延续自[上一个示例](#为自定义复杂度的开放式问题配置模板)。使用另一个模板更新插件配置：

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

现在，你应该能够通过同一条路由使用这两个模板。

向路由发送一个 POST 请求，使用第一个模板：

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "QnA with complexity",
    "complexity": "brief",
    "prompt": "quick sort"
  }'
```

你应该会收到类似于以下的响应：

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

向路由发送一个 POST 请求，使用第二个模板：

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "template_name": "echo",
    "prompt": "hello APISIX"
  }'
```

你应该会收到类似于以下的响应：

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
