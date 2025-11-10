---
title: ai-prompt-guard
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-prompt-guard
description: 本文档包含有关 Apache APISIX ai-prompt-guard 插件的信息。
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

`ai-prompt-guard` 插件通过检查和验证传入的提示消息来保护您的 AI 端点。它根据用户定义的允许和拒绝模式检查请求内容，确保只有经过批准的输入才会被处理。根据其配置，插件可以检查最新消息或整个对话历史，并且可以设置为检查所有角色的提示或仅检查最终用户的提示。

当同时配置了**允许**和**拒绝**模式时，插件首先确保至少匹配一个允许的模式。如果没有匹配，请求将被拒绝并返回 _"Request doesn't match allow patterns"_ 错误。如果找到允许的模式，它会检查是否存在任何拒绝模式的匹配——如果检测到任何匹配，则拒绝请求并返回 _"Request contains prohibited content"_ 错误。

## 插件属性

| **字段**                       | **必选项** | **类型**  | **描述**                                                                                                                                                      |
| ------------------------------ | ---------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| match_all_roles                | 否         | boolean   | 如果设置为 `true`，插件将检查所有角色的提示消息。否则，它只在角色为 `"user"` 时进行验证。默认值为 `false`。 |
| match_all_conversation_history | 否         | boolean   | 启用时，对话历史中的所有消息将被连接并检查。如果为 `false`，则只检查最后一条消息的内容。默认值为 `false`。 |
| allow_patterns                 | 否         | array     | 正则表达式模式列表。提供时，提示必须匹配**至少一个**模式才被认为是有效的。                                                      |
| deny_patterns                  | 否         | array     | 正则表达式模式列表。如果任何这些模式匹配提示内容，请求将被拒绝。                                                                  |

## 使用示例

创建一个带有 `ai-prompt-guard` 插件的路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/v1/chat/completions",
    "plugins": {
      "ai-prompt-guard": {
        "match_all_roles": true,
          "allow_patterns": [
            "goodword"
          ],
        "deny_patterns": [
          "badword"
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
  "messages": [{ "role": "user", "content": "badword request" }]
}' -H "Authorization: Bearer <your token here>"
```

请求将失败并返回 400 错误和以下响应。

```bash
{"message":"Request doesn't match allow patterns"}
```
