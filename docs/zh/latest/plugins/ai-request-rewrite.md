---
title: ai-request-rewrite
keywords:
  - Apache APISIX
  - AI 网关
  - Plugin
  - ai-request-rewrite
description: ai-request-rewrite 插件在客户端请求转发到上游服务之前拦截请求。它将预定义的提示与原始请求体一起发送到指定的 LLM 服务。LLM 处理输入并返回修改后的请求体，然后用于上游请求。这允许基于 AI 生成的内容动态转换 API 请求。
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

`ai-request-rewrite` 插件在客户端请求转发到上游服务之前拦截请求。它将预定义的提示与原始请求体一起发送到指定的 LLM 服务。LLM 处理输入并返回修改后的请求体，然后用于上游请求。这允许基于 AI 生成的内容动态转换 API 请求。

## 插件属性

| **字段**                 | **必选项** | **类型** | **描述**                                                                      |
| ------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------ |
| prompt                    | 是          | String   | 发送到 LLM 服务的提示。                                                      |
| provider                  | 是          | String   | LLM 服务的名称。可用选项：openai、deekseek、azure-openai、aimlapi、anthropic、openrouter、gemini、vertex-ai 和 openai-compatible。当选择 `aimlapi` 时，插件使用 OpenAI 兼容驱动程序，默认端点为 `https://api.aimlapi.com/v1/chat/completions`。   |
| provider_conf             | 否           | Object   | 特定提供商的配置。当 `provider` 设置为 `vertex-ai` 且未配置 `override` 时必填。 |
| provider_conf.project_id  | 是           | String   | Google Cloud 项目 ID。 |
| provider_conf.region      | 是           | String   | Google Cloud 区域。 |
| auth                      | 是          | Object   | 身份验证配置                                                         |
| auth.header               | 否           | Object   | 身份验证头部。键必须匹配模式 `^[a-zA-Z0-9._-]+$`。                  |
| auth.query                | 否           | Object   | 身份验证查询参数。键必须匹配模式 `^[a-zA-Z0-9._-]+$`。         |
| auth.gcp                  | 否           | Object   | Google Cloud Platform (GCP) 身份验证配置。 |
| auth.gcp.service_account_json | 否       | String   | GCP 服务账号 JSON 文件的内容。也可以通过设置“GCP_SERVICE_ACCOUNT”环境变量来配置。 |
| auth.gcp.max_ttl          | 否           | Integer  | 缓存 GCP 访问令牌的最大 TTL（秒）。最小值：1。 |
| auth.gcp.expire_early_secs| 否           | Integer  | 在访问令牌实际过期时间之前使其过期的秒数，以避免边缘情况。最小值：0。默认值：60。 |
| options                   | 否           | Object   | 模型的键/值设置                                                     |
| options.model             | 否           | String   | 要执行的模型。示例：openai 的 "gpt-3.5-turbo"，deekseek 的 "deepseek-chat"，或 openai-compatible 或 aimlapi 服务的 "qwen-turbo" |
| override.endpoint         | 否           | String   | 使用 OpenAI 兼容服务时覆盖默认端点（例如，自托管模型或第三方 LLM 服务）。当提供商为 'openai-compatible' 时，endpoint 字段是必需的。 |
| timeout                   | 否           | Integer  | 对 LLM 服务请求的总超时时间（毫秒），包括连接、发送和读取超时。范围：1 - 60000。默认值：30000|
| keepalive                 | 否           | Boolean  | 为对 LLM 服务的请求启用 keepalive。默认值：true                                  |
| keepalive_timeout         | 否           | Integer  | 对 LLM 服务请求的 keepalive 超时时间（毫秒）。最小值：1000。默认值：60000 |
| keepalive_pool            | 否           | Integer  | 对 LLM 服务请求的 keepalive 池大小。最小值：1。默认值：30                     |
| ssl_verify                | 否           | Boolean  | 对 LLM 服务请求的 SSL 验证。默认值：true                                  |

## 工作原理

![image](https://github.com/user-attachments/assets/c7288e4f-00fc-46ca-b69e-d3d74d7085ca)

## 示例

以下示例演示了如何为不同场景配置 `ai-request-rewrite`。

:::note

您可以使用以下命令从 config.yaml 获取 admin_key 并保存到环境变量中：

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')

:::

### 编辑敏感信息

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged.",
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

现在发送一个请求：

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john.doe@example.com",
    "credit_card": "4111 1111 1111 1111",
    "ssn": "123-45-6789",
    "address": "123 Main St"
  }'
```

发送到 LLM 服务的请求体如下：

```json
{
  "messages": [
     {
       "role": "system",
       "content": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged."
     },
     {
       "role": "user",
       "content": "{\n\"name\":\"John Doe\",\n\"email\":\"john.doe@example.com\",\n\"credit_card\":\"4111 1111 1111 1111\",\n\"ssn\":\"123-45-6789\",\n\"address\":\"123 Main St\"\n}"
     }
   ]
}

```

LLM 处理输入并返回修改后的请求体，将检测到的敏感值替换为掩码格式，然后用于上游请求：

```json
{
  "name": "John Doe",
  "email": "john.doe@example.com",
  "credit_card": "**** **** **** 1111",
  "ssn": "***-**-6789",
  "address": "123 Main St"
}
```

### 向 OpenAI 兼容的 LLM 发送请求

创建一个带有 `ai-request-rewrite` 插件的路由，将 `provider` 设置为 `openai-compatible`，并将模型的端点设置为 `override.endpoint`，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged.",
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "options": {
          "model": "qwen-plus",
          "max_tokens": 1024,
          "temperature": 1
        },
        "override": {
          "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```
