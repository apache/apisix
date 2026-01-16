---
title: ai-prompt-decorator
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-decorator
description: ai-prompt-decorator 插件插件通过前缀和后缀附加预先设计的提示词来装饰用户向大语言模型提交的提示，从而简化 API 操作和内容生成流程。
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

## 描述

`ai-prompt-decorator` 插件简化了对 OpenAI、Anthropic 等大语言模型提供商及其模型的访问。它通过在前缀和后缀附加预先设计的提示词来修饰用户输入的提示，从而为内容生成设置上下文。这种做法有助于模型在交互过程中按照期望的指导原则运行。

## 插件属性

| **字段**          | **是否必填**      | **类型** | **描述**                                     |
| ----------------- | --------------- | -------- | -------------------------------------------- |
| `prepend`         | 条件性必填\*      | Array    | 需要前置添加的提示对象数组。组。                         |
| `prepend.role`    | 是              | String   | 消息的角色，例如`system`、`user` 或 `assistant`。 |
| `prepend.content` | 是              | String   | 消息的内容（提示词）。                     |
| `append`          | 条件性必填\*      | Array    | 需要后置添加的提示对象数组。                         |
| `append.role`     | 是              | String   | 消息的角色，例如`system`、`user` 或 `assistant`。 |
| `append.content`  | 是              | String   | 消息的内容（提示词）。                      |

\* **条件性必填**：`prepend` 和 `append` 中至少需要提供一个。

## 示例

以下示例将使用 OpenAI 作为上游服务提供商。在开始前，请先创建一个 [OpenAI 账户](https://openai.com)和 [API 密钥](https://openai.com/blog/openai-api)。你可以选择将密钥保存到环境变量中，如下所示：

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

如果你使用的是其他大语言模型提供商，请参考其文档获取 API 密钥。

### 前置与后置消息

以下示例演示了如何配置 `ai-prompt-decorator` 插件，以在用户输入消息前添加系统消息，并在其后附加用户消息。

创建一个路由，指向聊天补全端点，并配置预先设置的提示模板，如下所示：

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
        }
      },
      "ai-prompt-decorator": {
        "prepend":[
          {
            "role": "system",
            "content": "请简要且概念性地回答。"
          }
        ],
        "append":[
          {
            "role": "user",
            "content": "在回答结尾用一个简单的类比来总结。"
          }
        ]
      }
    }
  }'
```

向该路由发送一个 POST 请求，在请求体中指定模型和一个示例消息：

```shell
curl "http://127.0.0.1:9080/v1/chat/completions" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{ "role": "user", "content": "什么是 mTLS 认证？" }]
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
        "content": "双向 TLS (mTLS) 认证是一种安全协议，确保客户端和服务器在建立连接前相互验证对方身份。这种双向认证是通过交换和验证数字证书来实现的，这些证书是经过密码学签名的凭证，用于证明各方的身份。与标准 TLS 仅认证服务器不同，mTLS 增加了额外的信任层，也对客户端进行验证，为敏感通信提供更高的安全性。\n\n可以把 mTLS 想象成两位朋友在俱乐部见面时的秘密握手。双方都必须知道这个握手动作才能进入，确保他们在入场前彼此认出并互相信任。",
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
