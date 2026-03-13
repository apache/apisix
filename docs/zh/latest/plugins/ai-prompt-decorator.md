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

## 描述

`ai-prompt-decorator` 插件通过在请求中追加或前置提示，简化了对 LLM 提供商（如 OpenAI 和 Anthropic）及其模型的访问。

## 插件属性

| **字段**          | **必选项**      | **类型** | **描述**                                     |
| ----------------- | --------------- | -------- | -------------------------------------------- |
| `prepend`         | 条件必选\*      | Array    | 要前置的提示对象数组                         |
| `prepend.role`    | 是              | String   | 消息的角色（`system`、`user`、`assistant`） |
| `prepend.content` | 是              | String   | 消息的内容。最小长度：1                      |
| `append`          | 条件必选\*      | Array    | 要追加的提示对象数组                         |
| `append.role`     | 是              | String   | 消息的角色（`system`、`user`、`assistant`） |
| `append.content`  | 是              | String   | 消息的内容。最小长度：1                      |

\* **条件必选**：必须提供 `prepend` 或 `append` 中的至少一个。

## 使用示例

创建一个带有 `ai-prompt-decorator` 插件的路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/v1/chat/completions",
    "plugins": {
      "ai-prompt-decorator": {
        "prepend":[
          {
            "role": "system",
            "content": "我明天有考试，所以请简要地从概念上解释"
          }
        ],
        "append":[
          {
            "role": "system",
            "content": "用一个类比来结束回答。"
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "api.openai.com:443": 1
      },
      "pass_host": "node",
      "scheme": "https"
    }
  }'
```

现在发送一个请求：

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i -XPOST  -H 'Content-Type: application/json' -d '{
  "model": "gpt-4",
  "messages": [{ "role": "user", "content": "什么是 TLS 握手？" }]
}' -H "Authorization: Bearer <your token here>"
```

然后请求体将被修改为类似这样：

```json
{
  "model": "gpt-4",
  "messages": [
    {
      "role": "system",
      "content": "我明天有考试，所以请简要地从概念上解释"
    },
    { "role": "user", "content": "什么是 TLS 握手？" },
    {
      "role": "system",
      "content": "用一个类比来结束回答。"
    }
  ]
}
```
