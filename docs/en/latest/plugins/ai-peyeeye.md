---
title: ai-peyeeye
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-peyeeye
  - PII
description: This document contains information about the Apache APISIX ai-peyeeye Plugin.
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

The `ai-peyeeye` Plugin redacts PII from prompts before they reach the upstream
LLM and rehydrates the model's response so end users see the original values.

It calls the [peyeeye.ai](https://peyeeye.ai) `/v1/redact` and `/v1/rehydrate`
HTTP API. Two session modes are supported:

- `stateful` (default): peyeeye stores the token-to-value map under a `ses_…`
  id; the rehydrate request references the id.
- `stateless`: peyeeye returns a sealed `skey_…` blob and retains nothing
  server-side.

The Plugin is designed to be used together with the
[`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) Plugin
on the same Route. It runs at priority `1074`, ahead of `ai-proxy` (1040), so
the redacted prompt is what the AI provider sees.

### Behavior invariants

- **Length-guard.** If `/v1/redact` returns a different number of texts than
  were sent, or returns an unexpected response shape, the Plugin fails the
  request with `HTTP 500` rather than forwarding partially-redacted (or
  unredacted) text upstream.
- **Auth required.** If `api_key` is not supplied (in config or via the
  `PEYEEYE_API_KEY` environment variable), schema validation fails.
- **Best-effort rehydrate.** If `/v1/rehydrate` fails the Plugin leaves the
  model's redacted output unchanged rather than risk leaking PII.
- **Best-effort cleanup.** Stateful sessions are `DELETE`'d after rehydrate;
  failures are logged but do not affect the response.

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `api_key` | string | True (or `PEYEEYE_API_KEY` env) | | | peyeeye API key; sent as `Authorization: Bearer <key>`. |
| `api_base` | string | False | `https://api.peyeeye.ai` | | Override the peyeeye API base URL (e.g. for self-hosted instances or test fixtures). |
| `locale` | string | False | `auto` | BCP-47 | Locale hint passed to `/v1/redact`. |
| `entities` | array[string] | False | | | Optional whitelist of peyeeye entity ids to detect. When omitted the server uses its default set. |
| `session_mode` | string | False | `stateful` | `stateful`, `stateless` | Whether peyeeye retains the token map (`stateful`) or returns a sealed blob (`stateless`). |
| `timeout` | integer | False | 15000 | >= 1 | HTTP timeout in milliseconds for calls to the peyeeye API. |
| `keepalive` | boolean | False | true | | Reuse upstream connection pool. |
| `keepalive_pool` | integer | False | 30 | >= 1 | Connection pool size when `keepalive` is true. |
| `keepalive_timeout` | integer | False | 60000 | >= 1000 | Idle keepalive timeout in milliseconds. |
| `ssl_verify` | boolean | False | true | | Whether to verify the peyeeye TLS certificate. |

The `api_key` field is encrypted at rest when `data_encryption` is enabled.

## Example

The following Route redacts PII via peyeeye and proxies to OpenAI:

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

A request like:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "My email is alice@example.com, please summarise it." }
    ]
  }'
```

is rewritten to `My email is [EMAIL_1], please summarise it.` before reaching
OpenAI. The response is then rewritten in the reverse direction so the client
sees the original email address.
