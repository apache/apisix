---
title: ai-aws-content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-aliyun-content-moderation
description: 本文档包含有关 Apache APISIX ai-aws-content-moderation 插件的信息.
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the 不TICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may 不t use this file except in compliance with
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

## Description

ai-aliyun-content-moderation 插件与阿里云的内容审核服务集成，用于在使用 LLM 时检查请求和响应内容中是否存在不当内容。它支持实时流式传输检查和最终数据包审核。.

此插件必须在使用 ai-proxy 或 ai-proxy-multi 插件的路由中使用.

## 插件属性

| **场地**                   | **必需的** | **类型**  | **描述**                                                                                                                                                             |
| ---------------------------- | ------------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| endpoint                     | 是的          | String    | 阿里云服务端点 URL                                                                                                                                                 |
| region_id                    | 是的          | String    | 阿里云区域 identifier                                                                                                                                                    |
| access_key_id                | 是的          | String    | 阿里云访问密钥ID                                                                                                                                                        |
| access_key_secret            | 是的          | String    | 阿里云访问密钥 secret                                                                                                                                                    |
| check_request                | 不           | Boolean   | 启用请求内容审核。默认值： `true`                                                                                                                          |
| check_response               | 不           | Boolean   | 启用回复内容审核。默认值： `false`                                                                                                                        |
| stream_check_mode            | 不           | String    | 流媒体审核模式。默认值： `"final_packet"`. 有效值： `["realtime", "final_packet"]`                                                                           |
| stream_check_cache_size      | 不           | Integer   | 实时模式下每个审核批次的最大字符数。默认值： `128`. 必须是 `>= 1`.                                                                                        |
| stream_check_interval        | 不           | Number    | 实时模式下批量检查的间隔秒数。默认值： `3`. 必须是 `>= 0.1`.                                                                                              |
| request_check_service        | 不           | String    | 阿里云请求审核服务。默认值： `"llm_query_moderation"`                                                                                                    |
| request_check_length_limit   | 不           | Number    |每个请求审核块的最大字符数。默认值： `2000`.                                                                                                               |
| response_check_service       | 不           | String    | 阿里云服务用于回复审核。默认值：`"llm_response_moderation"`                                                                                               |
| response_check_length_limit  | 不           | Number    | 每个响应审核块的最大字符数。默认值： `5000`.                                                                                                              |
| risk_level_bar               | 不           | String    | 内容拒绝的阈值。默认值： `"high"`. 有效值： `["不ne", "low", "medium", "high", "max"]`                                                                |
| deny_code                    | 不           | Number    | 被拒绝内容的 HTTP 状态代码。默认值： `200`.                                                                                                                      |
| deny_message                 | 不           | String    | 被拒绝内容的自定义消息。默认值： `-`.                                                                                                                           |
| timeout                      | 不           | Integer   | 请求超时（以毫秒为单位）。默认值：10000。必须为 >=1`.                                                                                                          |
| ssl_verify                   | 不           | Boolean   | 启用 SSL 证书验证。默认值： `true`.                                                                                                                       |

## 示例用法

首先初始化这些 shell 变量:

```shell
ADMIN_API_KEY=edd1c9f034335f136f87ad84b625c8f1
ALIYUN_ACCESS_KEY_ID=your-aliyun-access-key-id
ALIYUN_ACCESS_KEY_SECRET=your-aliyun-access-key-secret
ALIYUN_REGION=cn-hangzhou
ALIYUN_ENDPOINT=https://green.cn-hangzhou.aliyuncs.com
OPENAI_KEY=your-openai-api-key
```

使用 `ai-aliyun-content-moderation` 和 `ai-proxy` 插件创建路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/v1/chat/completions",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_KEY"'"
          }
        },
        "override": {
          "endpoint": "http://localhost:6724/v1/chat/completions"
        }
      },
      "ai-aliyun-content-moderation": {
        "endpoint": "'"$ALIYUN_ENDPOINT"'",
        "region_id": "'"$ALIYUN_REGION"'",
        "access_key_id": "'"$ALIYUN_ACCESS_KEY_ID"'",
        "access_key_secret": "'"$ALIYUN_ACCESS_KEY_SECRET"'",
        "risk_level_bar": "high",
        "check_request": true,
        "check_response": true,
        "deny_code": 400,
        "deny_message": "Your request violates content policy"
      }
    }
  }'
```

这里使用了 `ai-proxy` 插件，因为它简化了对 LLM 的访问。不过，您也可以在上游配置中配置 LLM。

现在发送请求：

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "I want to kill you"}
    ],
    "stream": false
  }'
```

然后请求将被阻止并出现如下错误：

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json

{"id":"chatcmpl-123","object":"chat.completion","model":"gpt-3.5-turbo","choices":[{"index":0,"message":{"role":"assistant","content":"Your request violates content policy"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}}
```
