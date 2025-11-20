---
title: ai-prompt-template
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-template
description: 本文档包含有关 Apache APISIX ai-prompt-template 插件的信息。
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

`ai-prompt-template` 插件通过使用模板预定义请求格式，简化了对 LLM 提供商（如 OpenAI 和 Anthropic）及其模型的访问，只允许用户将自定义值传递到模板变量中。

## 插件属性

| **字段**                              | **必选项** | **类型** | **描述**                                                                                                             |
| ------------------------------------- | ---------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| `templates`                           | 是         | Array    | 模板对象数组                                                                                                |
| `templates.name`                      | 是         | String   | 模板的名称。                                                                                                       |
| `templates.template.model`            | 是         | String   | AI 模型的名称，例如 `gpt-4` 或 `gpt-3.5`。有关更多可用模型，请参阅您的 LLM 提供商 API 文档。 |
| `templates.template.messages.role`    | 是         | String   | 消息的角色（`system`、`user`、`assistant`）                                                                         |
| `templates.template.messages.content` | 是         | String   | 消息的内容。                                                                                                     |

## 使用示例

创建一个带有 `ai-prompt-template` 插件的路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/v1/chat/completions",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "api.openai.com:443": 1
      },
      "scheme": "https",
      "pass_host": "node"
    },
    "plugins": {
      "ai-prompt-template": {
        "templates": [
          {
            "name": "详细程度",
            "template": {
              "model": "gpt-4",
              "messages": [
                {
                  "role": "user",
                  "content": "用{{ level }}的方式解释{{ topic }}。"
                }
              ]
            }
          }
        ]
      }
    }
  }'
```

现在发送一个请求：

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i -XPOST  -H 'Content-Type: application/json' -d '{
  "template_name": "详细程度",
  "topic": "心理学",
  "level": "简要"
}' -H "Authorization: Bearer <your token here>"
```

然后请求体将被修改为类似这样：

```json
{
  "model": "some model",
  "messages": [
    { "role": "user", "content": "用简要的方式解释心理学。" }
  ]
}
```
