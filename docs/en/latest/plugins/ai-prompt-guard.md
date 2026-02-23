---
title: ai-prompt-guard
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-guard
description: This document contains information about the Apache APISIX ai-prompt-guard Plugin.
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

The `ai-prompt-guard` plugin safeguards your AI endpoints by inspecting and validating incoming prompt messages. It checks the content of requests against user-defined allowed and denied patterns to ensure that only approved inputs are processed. Based on its configuration, the plugin can either examine just the latest message or the entire conversation history, and it can be set to check prompts from all roles or only from end users.

When both **allow** and **deny** patterns are configured, the plugin first ensures that at least one allowed pattern is matched. If none match, the request is rejected with a _"Request doesn't match allow patterns"_ error. If an allowed pattern is found, it then checks for any occurrences of denied patterns—rejecting the request with a _"Request contains prohibited content"_ error if any are detected.

## Plugin Attributes

| **Field**                      | **Required** | **Type**  | **Description**                                                                                                                                                      |
| ------------------------------ | ------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| match_all_roles                | No           | boolean   | If set to `true`, the plugin will check prompt messages from all roles. Otherwise, it only validates when its role is `"user"`. Default is `false`. |
| match_all_conversation_history | No           | boolean   | When enabled, all messages in the conversation history are concatenated and checked. If `false`, only the content of the last message is examined. Default is `false`. |
| allow_patterns                 | No           | array     | A list of regex patterns. When provided, the prompt must match **at least one** pattern to be considered valid.                                                      |
| deny_patterns                  | No           | array     | A list of regex patterns. If any of these patterns match the prompt content, the request is rejected.                                                                  |

## Example usage

Create a route with the `ai-prompt-guard` plugin like so:

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

Now send a request:

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i -XPOST  -H 'Content-Type: application/json' -d '{
  "model": "gpt-4",
  "messages": [{ "role": "user", "content": "badword request" }]
}' -H "Authorization: Bearer <your token here>"
```

The request will fail with 400 error and following response.

```bash
{"message":"Request doesn't match allow patterns"}
```
