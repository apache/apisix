---
title: ai-aws-content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-aws-content-moderation
description: This document contains information about the Apache APISIX ai-aws-content-moderation Plugin.
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

## Description

The `ai-aws-content-moderation` plugin processes the request body to check for toxicity and rejects the request if it exceeds the configured threshold.

**_This plugin must be used in routes that proxy requests to LLMs only._**

**_As of now, the plugin only supports the integration with [AWS Comprehend](https://aws.amazon.com/comprehend/) for content moderation. PRs for introducing support for other service providers are welcomed._**

## Plugin Attributes

| **Field**                    | **Required** | **Type** | **Description**                                                                                                                                                                                                                                         |
| ---------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| comprehend.access_key_id     | Yes          | String   | AWS access key ID                                                                                                                                                                                                                                       |
| comprehend.secret_access_key | Yes          | String   | AWS secret access key                                                                                                                                                                                                                                   |
| comprehend.region            | Yes          | String   | AWS region                                                                                                                                                                                                                                              |
| comprehend.endpoint          | No           | String   | AWS Comprehend service endpoint. Must match the pattern `^https?://`                                                                                                                                                                                    |
| comprehend.ssl_verify        | No           | String   | Enables SSL certificate verification.                                                                                                                                                                                                                   |
| moderation_categories        | No           | Object   | Key-value pairs of moderation category and their score. In each pair, the key should be one of the `PROFANITY`, `HATE_SPEECH`, `INSULT`, `HARASSMENT_OR_ABUSE`, `SEXUAL`, or `VIOLENCE_OR_THREAT`; and the value should be between 0 and 1 (inclusive). |
| moderation_threshold         | No           | Number   | The degree to which content is harmful, offensive, or inappropriate. A higher value indicates more toxic content allowed. Range: 0 - 1. Default: 0.5                                                                                                    |

## Example usage

First initialise these shell variables:

```shell
ADMIN_API_KEY=edd1c9f034335f136f87ad84b625c8f1
ACCESS_KEY_ID=aws-comprehend-access-key-id-here
SECRET_ACCESS_KEY=aws-comprehend-secret-access-key-here
OPENAI_KEY=open-ai-key-here
```

Create a route with the `ai-aws-content-moderation` and `ai-proxy` plugin like so:

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

The `ai-proxy` plugin is used here as it simplifies access to LLMs. However, you may configure the LLM in the upstream configuration as well.

Now send a request:

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

Then the request will be blocked with error like this:

```text
HTTP/1.1 400 Bad Request
Date: Thu, 03 Oct 2024 11:53:15 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.10.0

request body exceeds PROFANITY threshold
```

Send a request with compliant content in the request body:

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

This request will be proxied normally to the configured LLM.

```text
HTTP/1.1 200 OK
Date: Thu, 03 Oct 2024 11:53:00 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.10.0

{"choices":[{"finish_reason":"stop","index":0,"message":{"content":"1+1 equals 2.","role":"assistant"}}],"created":1727956380,"id":"chatcmpl-AEEg8Pe5BAW5Sw3C1gdwXnuyulIkY","model":"gpt-4o-2024-05-13","object":"chat.completion","system_fingerprint":"fp_67802d9a6d","usage":{"completion_tokens":7,"prompt_tokens":23,"total_tokens":30}}
```

You can also configure filters on other moderation categories like so:

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

If none of the `moderation_categories` are configured, request bodies will be moderated on the basis of overall toxicity.
The default `moderation_threshold` is 0.5, it can be configured like so.

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
