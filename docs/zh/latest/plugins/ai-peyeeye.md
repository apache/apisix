---
title: ai-peyeeye
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - ai-peyeeye
  - PII
description: 本文介绍了 Apache APISIX ai-peyeeye 插件的相关操作，你可以使用此插件在请求转发到 LLM 之前，调用 peyeeye.ai 对消息中的个人身份信息（PII）进行脱敏，并在响应返回时进行还原。
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

`ai-peyeeye` 插件在请求转发到上游 LLM 之前，将提示词中的 PII 信息脱敏，并在
响应返回客户端时将占位符还原为原始值。

插件调用 [peyeeye.ai](https://peyeeye.ai) 的 `/v1/redact` 与 `/v1/rehydrate`
HTTP API，支持两种会话模式：

- `stateful`（默认）：peyeeye 在服务端保存 token 到原始值的映射，并返回
  `ses_…` 会话 ID；
- `stateless`：peyeeye 返回一个加密封装的 `skey_…` 字符串，服务端不保留任何
  状态。

该插件需与同一路由上的 [`ai-proxy`](./ai-proxy.md) 或
[`ai-proxy-multi`](./ai-proxy-multi.md) 插件一起使用，其优先级为 `1074`，
高于 `ai-proxy` (1040)，因此 AI 服务收到的将是已脱敏的请求。

### 行为不变量

- **长度保护**：若 `/v1/redact` 返回的文本数量与请求不一致，或返回结构异常，
  插件将以 `HTTP 500` 拒绝请求，绝不向上游转发未脱敏内容。
- **必须配置鉴权**：若 `api_key` 未配置且环境变量 `PEYEEYE_API_KEY` 未设置，
  schema 校验失败。
- **还原失败回退**：当 `/v1/rehydrate` 调用失败时，保留模型的已脱敏输出，
  避免泄露 PII。
- **会话清理**：有状态会话在还原后会发起最优先级的 `DELETE` 调用，失败仅记录
  日志，不影响响应。

## 属性

| 名称 | 类型 | 必选 | 默认值 | 有效值 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `api_key` | string | 是（或 `PEYEEYE_API_KEY` 环境变量） | | | peyeeye API Key，作为 `Authorization: Bearer <key>` 头发送。 |
| `api_base` | string | 否 | `https://api.peyeeye.ai` | | peyeeye API 基础 URL（可用于自托管实例或测试环境）。 |
| `locale` | string | 否 | `auto` | BCP-47 | 传给 `/v1/redact` 的语言提示。 |
| `entities` | array[string] | 否 | | | 可选的实体白名单，仅检测列表中的实体；缺省时使用服务端默认集合。 |
| `session_mode` | string | 否 | `stateful` | `stateful`, `stateless` | 是否在服务端保存 token 映射。 |
| `timeout` | integer | 否 | 15000 | >= 1 | 调用 peyeeye API 的 HTTP 超时（毫秒）。 |
| `keepalive` | boolean | 否 | true | | 是否使用上游连接池。 |
| `keepalive_pool` | integer | 否 | 30 | >= 1 | 连接池大小。 |
| `keepalive_timeout` | integer | 否 | 60000 | >= 1000 | 空闲 keepalive 超时（毫秒）。 |
| `ssl_verify` | boolean | 否 | true | | 是否校验 peyeeye TLS 证书。 |

启用 `data_encryption` 时 `api_key` 字段会在存储中加密。

## 示例

下面的路由配置使用 peyeeye 进行 PII 脱敏，并通过 `ai-proxy` 转发到 OpenAI：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-peyeeye": {
        "api_key": "'"$PEYEEYE_API_KEY"'",
        "session_mode": "stateful"
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4o-mini"
        }
      }
    }
  }'
```

请求示例：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "我的邮箱是 alice@example.com，请帮我总结一下。" }
    ]
  }'
```

会被改写为 `我的邮箱是 [EMAIL_1]，请帮我总结一下。` 再发往 OpenAI；响应阶段
则反向替换，客户端最终看到原始邮箱地址。
