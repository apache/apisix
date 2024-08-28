---
title: ai-prompt-template
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-template
description: This document contains information about the Apache APISIX ai-prompt-template Plugin.
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

The `ai-prompt-decorator` plugin simplifies access to LLM providers, such as OpenAI and Anthropic, and their models by appending or prepending

## Plugin Attributes

| **Field**                             | **Required** | **Type** | **Description**                                     |
| ------------------------------------- | ------------ | -------- | --------------------------------------------------- |
| `templates`                           | Yes          | Array    | An array of template objects                        |
| `templates.name`                      | Yes          | String   | Name of the template.                               |
| `templates.template.model`            | Yes          | String   | Model of the AI Model. Example: gpt-4, gpt-3.5      |
| `templates.template.messages.role`    | Yes          | String   | Role of the message (`system`, `user`, `assistant`) |
| `templates.template.messages.content` | Yes          | String   | Content of the message.                             |

## Example usage

Create a route with the `ai-prompt-template` plugin like so:

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
            "name": "level of detail",
            "template": {
              "model": "gpt-4",
              "messages": [
                {
                  "role": "user",
                  "content": "Explain about {{ topic }} in {{ level }}."
                }
              ]
            }
          }
        ]
      }
    }
  }'
```

Now send a request:

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i -XPOST  -H 'Content-Type: application/json' -d '{
  "template_name": "level of detail,
  "topic": "psychology",
  "level": "brief"
}' -H "Authorization: Bearer <your token here>"
```

Then the request body will be modified to something like this:

```json
{
  "model": "some model",
  "messages": [
    { "role": "user", "content": "Explain about psychology in brief." }
  ]
}
```
