---
title: ai-prompt-decorator
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-decorator
description: This document contains information about the Apache APISIX ai-prompt-decorator Plugin.
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

The `ai-prompt-decorator` plugin simplifies access to AI providers and models by appending or prepending
prompts into the request.

## Plugin Attributes

| **Field**         | **Type** | **Description**                                     | **Required**    |
| ----------------- | -------- | --------------------------------------------------- | --------------- |
| `prepend`         | Array    | An array of prompt objects to be prepended          | Conditionally\* |
| `prepend.role`    | String   | Role of the message (`system`, `user`, `assistant`) | Yes             |
| `prepend.content` | String   | Content of the message. Minimum length: 1           | Yes             |
| `append`          | Array    | An array of prompt objects to be appended           | Conditionally\* |
| `append.role`     | String   | Role of the message (`system`, `user`, `assistant`) | Yes             |
| `append.content`  | String   | Content of the message. Minimum length: 1           | Yes             |

\* **Conditionally Required**: At least one of `prepend` or `append` must be provided.

## Example usage

Create a route with the `ai-prompt-decorator` plugin like so:

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
            "content": "I have exams tomorrow so explain conceptually and briefly"
          }
        ],
        "append":[
          {
            "role": "system",
            "content": "End the response with an analogy."
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "api.openai.com": 1
      }
    }
  }'
```

The upstream node can be any arbitrary value because it won't be contacted.

Now send a request:

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i -XPOST  -H 'Content-Type: application/json' -d '{
  "model": "gpt-4",
  "messages": [{ "role": "user", "content": "What is TLS Handshake?" }]
}'
```

Then the request body will be modified to something like this:

```json
{
  "model": "gpt-4",
  "messages": [
    {
      "role": "system",
      "content": "I have exams tomorrow so explain conceptually and briefly"
    },
    { "role": "user", "content": "What is TLS Handshake?" },
    {
      "role": "system",
      "content": "End the response with an analogy."
    }
  ]
}
```
