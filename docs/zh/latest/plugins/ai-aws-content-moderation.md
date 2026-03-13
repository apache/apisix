---
title: ai-aws-content-moderation
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-aws-content-moderation
  - AWS
  - 内容审核
description: 本文档包含有关 Apache APISIX ai-aws-content-moderation 插件的信息。
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

`ai-aws-content-moderation` 插件处理请求体以检查毒性内容，如果超过配置的阈值则拒绝请求。

**_此插件只能在代理请求到 LLM 的路由中使用。_**

**_目前，该插件仅支持与 [AWS Comprehend](https://aws.amazon.com/comprehend/) 的集成进行内容审核。欢迎提交 PR 以引入对其他服务提供商的支持。_**

## 插件属性

| **字段**                     | **必选项** | **类型** | **描述**                                                                                                                                                                                                                                                |
| ---------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| comprehend.access_key_id     | 是         | String   | AWS 访问密钥 ID                                                                                                                                                                                                                                         |
| comprehend.secret_access_key | 是         | String   | AWS 秘密访问密钥                                                                                                                                                                                                                                       |
| comprehend.region            | 是         | String   | AWS 区域                                                                                                                                                                                                                                                |
| comprehend.endpoint          | 否         | String   | AWS Comprehend 服务端点。必须匹配模式 `^https?://`                                                                                                                                                                                                      |
| comprehend.ssl_verify        | 否         | String   | 启用 SSL 证书验证                                                                                                                                                                                                                                       |
| moderation_categories        | 否         | Object   | 审核类别及其分数的键值对。在每个对中，键应该是 `PROFANITY`、`HATE_SPEECH`、`INSULT`、`HARASSMENT_OR_ABUSE`、`SEXUAL` 或 `VIOLENCE_OR_THREAT` 之一；值应该在 0 和 1 之间（包含）                                                                      |
| moderation_threshold         | 否         | Number   | 内容有害、冒犯或不当的程度。较高的值表示允许更多毒性内容。范围：0 - 1。默认值：0.5                                                                                                                                                                      |

## 使用示例

首先初始化这些 shell 变量：

```shell
ADMIN_API_KEY=edd1c9f034335f136f87ad84b625c8f1
ACCESS_KEY_ID=aws-comprehend-access-key-id-here
SECRET_ACCESS_KEY=aws-comprehend-secret-access-key-here
OPENAI_KEY=open-ai-key-here
```

创建一个带有 `ai-aws-content-moderation` 和 `ai-proxy` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$ACCESS_KEY_ID"'",
          "secret_access_key": "'"$SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 0.5
        }
      },
      "ai-proxy": {
        "auth": {
          "header": {
            "api-key": "'"$OPENAI_KEY"'"
          }
        },
        "model": {
          "provider": "openai",
          "name": "gpt-4",
          "options": {
            "max_tokens": 512,
            "temperature": 1.0
          }
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

这里使用 `ai-proxy` 插件是因为它简化了对 LLM 的访问。不过，您也可以在上游配置中配置 LLM。

现在发送一个请求：

```shell
curl http://127.0.0.1:9080/post -i -XPOST  -H 'Content-Type: application/json' -d '{
  "messages": [
    {
      "role": "user",
      "content": "<very profane message here>"
    }
  ]
}'
```

然后请求将被阻止，并返回如下错误：

```text
HTTP/1.1 400 Bad Request
Date: Thu, 03 Oct 2024 11:53:15 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.10.0

request body exceeds PROFANITY threshold
```

发送一个在请求体中包含合规内容的请求：

```shell
curl http://127.0.0.1:9080/post -i -XPOST  -H 'Content-Type: application/json' -d '{
  "messages": [
    {
      "role": "system",
      "content": "You are a mathematician"
    },
    { "role": "user", "content": "What is 1+1?" }
  ]
}'
```

此请求将正常代理到配置的 LLM。

```text
HTTP/1.1 200 OK
Date: Thu, 03 Oct 2024 11:53:00 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.10.0

{"choices":[{"finish_reason":"stop","index":0,"message":{"content":"1+1 equals 2.","role":"assistant"}}],"created":1727956380,"id":"chatcmpl-AEEg8Pe5BAW5Sw3C1gdwXnuyulIkY","model":"gpt-4o-2024-05-13","object":"chat.completion","system_fingerprint":"fp_67802d9a6d","usage":{"completion_tokens":7,"prompt_tokens":23,"total_tokens":30}}
```

您还可以配置其他审核类别的过滤器，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$ACCESS_KEY_ID"'",
          "secret_access_key": "'"$SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 0.5,
          "HARASSMENT_OR_ABUSE": 0.7,
          "SEXUAL": 0.2
        }
      },
      "ai-proxy": {
        "auth": {
          "header": {
            "api-key": "'"$OPENAI_KEY"'"
          }
        },
        "model": {
          "provider": "openai",
          "name": "gpt-4",
          "options": {
            "max_tokens": 512,
            "temperature": 1.0
          }
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

如果没有配置任何 `moderation_categories`，请求体将基于整体毒性进行审核。
默认的 `moderation_threshold` 是 0.5，可以这样配置。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
  "uri": "/post",
  "plugins": {
    "ai-aws-content-moderation": {
      "provider": {
        "comprehend": {
          "access_key_id": "'"$ACCESS_KEY_ID"'",
          "secret_access_key": "'"$SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        }
      },
      "moderation_threshold": 0.7,
      "llm_provider": "openai"
    },
    "ai-proxy": {
      "auth": {
        "header": {
          "api-key": "'"$OPENAI_KEY"'"
        }
      },
      "model": {
        "provider": "openai",
        "name": "gpt-4",
        "options": {
          "max_tokens": 512,
          "temperature": 1.0
        }
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
