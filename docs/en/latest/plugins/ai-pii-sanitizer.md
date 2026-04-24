---
title: ai-pii-sanitizer
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-pii-sanitizer
description: This document contains information about the Apache APISIX ai-pii-sanitizer Plugin.
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

The `ai-pii-sanitizer` Plugin scrubs personally identifiable information (PII) and other secrets out of LLM traffic using regex-based detectors and Unicode hardening. It runs on the request side before the body reaches the upstream LLM (and optionally on the response side before the body reaches the client), replacing detections with stable placeholders such as `[EMAIL_0]`.

The Plugin is pure Lua with no external dependencies. It is designed to be used together with [ai-proxy](./ai-proxy.md) or [ai-proxy-multi](./ai-proxy-multi.md).

### Built-in categories

| Name | What it detects |
| --- | --- |
| `email` | Standard RFC-ish email addresses |
| `us_ssn` | US Social Security Numbers (with invalid-range filtering) |
| `credit_card` | 12–19 digit PANs; Luhn-validated to suppress false positives |
| `phone` | E.164 or US-formatted phone numbers |
| `ipv4` / `ipv6` | IP addresses |
| `iban` | International Bank Account Numbers |
| `aws_access_key` | `AKIA…` / `ASIA…` access key IDs |
| `openai_key` | `sk-…` API keys |
| `github_token` | `ghp_…` / `gho_…` / `ghu_…` / `ghs_…` / `ghr_…` tokens |
| `jwt` | Three-segment `eyJ…` JWTs |
| `generic_api_key` | Heuristic `api_key:/token:/secret:` values |
| `bearer_token` | `Bearer …` headers embedded in text |

Custom patterns can be added via `custom_patterns`.

### Unicode hardening

Attackers bypass regex scanners by injecting zero-width characters, bidirectional overrides, or Unicode-compatibility variants into PII strings. The Plugin hardens against this by NFKC-normalizing input, then stripping zero-width and bidi code points, before applying the regex pass. Hardening is on by default; see the `unicode` attribute to tune.

### Vault and unmask-on-response

With `restore_on_response: true`, every masked value is stored in a per-request vault and substituted back into the LLM's response on its way to the client. This keeps PII off the wire to the LLM provider while still letting the client receive a useful response that references the original values. A short preamble is automatically prepended to the request instructing the LLM to preserve placeholders verbatim.

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `direction` | string | False | `input` | `input`, `output`, `both` | Which side to scan. `input` rewrites the request body going upstream; `output` rewrites the response body going to the client. |
| `action` | string | False | `mask` | `mask`, `redact`, `block`, `alert` | Default action applied to every hit. `mask` replaces with a placeholder, `redact` deletes the match, `block` rejects the request, `alert` masks and logs. |
| `categories` | array | False | all built-in | see table above or object form | If omitted, all built-in categories are enabled. Pass `[]` to disable all built-ins. Each entry may be a string (name) or an object `{name, action?, mask_style?}` to override `action` / `mask_style` per category. |
| `custom_patterns` | array | False | `[]` | see schema below | Extra regex patterns applied after the built-ins. |
| `allowlist` | array | False | `[]` | strings | Literal strings to leave untouched even if they match a category regex. |
| `unicode.strip_zero_width` | boolean | False | `true` | | Strip U+200B/C/D, U+2060, U+FEFF. |
| `unicode.strip_bidi` | boolean | False | `true` | | Strip U+202A-E and U+2066-9 (Trojan-Source defenses). |
| `unicode.normalize` | string | False | `nfkc` | `nfkc`, `none` | NFKC-normalize before scanning. `none` preserves exact bytes but leaves the regex bypass-able via Unicode compatibility variants. |
| `mask_style` | string | False | `tag` | `tag`, `tag_flat`, `partial`, `hash` | Placeholder format. `tag` uses stable-per-value tokens (`[EMAIL_0]`, `[EMAIL_1]`) — required for `restore_on_response`. `tag_flat` uses bare `[EMAIL]`. `partial` shows first two characters plus tag. `hash` adds the first 8 chars of the MD5. |
| `restore_on_response` | boolean | False | `false` | | If `true`, placeholders in the LLM response are substituted back with their original values before returning to the client. |
| `preamble.enable` | boolean | False | `true` | | When `restore_on_response` is on, prepend a short system message instructing the LLM to preserve placeholders verbatim. |
| `preamble.content` | string | False | built-in default | | Override the preamble text. |
| `stream_buffer_mode` | boolean | False | `false` | | If `true`, buffers the full streaming response before scanning (simpler, loses streaming UX). Default per-chunk scan is fast but may miss PII that straddles SSE chunk boundaries. |
| `log_detections` | boolean | False | `true` | | Emit an `info` log line enumerating per-category hit counts. |
| `log_payload` | boolean | False | `false` | | Include the raw payload in detection logs. **Off by default** to avoid leaking PII to logs. |
| `on_block.status` | integer | False | `400` | 200–599 | HTTP status when `action: block` triggers. |
| `on_block.body` | string | False | sensible default | | Response body when `action: block` triggers. |

### `custom_patterns[]` schema

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | Yes | Identifier used in logs and in `[NAME_N]` placeholders. |
| `pattern` | string | Yes | ngx.re-compatible regex. |
| `replace_with` | string | No | Static replacement. If omitted, falls back to the stable-per-value placeholder format. |
| `action` | string | No | Override the top-level `action` for this pattern. |

## Examples

The following examples use OpenAI as the upstream LLM. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api), then save it as:

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### Mask PII on the way to the LLM

Create a Route that proxies to OpenAI and masks email / phone / credit card in the request:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4" }
      },
      "ai-pii-sanitizer": {
        "direction": "input",
        "categories": ["email", "phone", "credit_card"]
      }
    }
  }'
```

Send a request containing PII:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "Email alice@acme.com about charge on 4532015112830366" }
    ]
  }'
```

The upstream LLM sees `Email [EMAIL_0] about charge on [CREDIT_CARD_0]`. Your client receives the model's reply referencing the same placeholders.

### Unmask on response

To give the client a useful response that references real values while still keeping PII off the wire to the LLM, turn on `restore_on_response`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4" }
      },
      "ai-pii-sanitizer": {
        "direction": "input",
        "categories": ["email", "phone"],
        "restore_on_response": true
      }
    }
  }'
```

Now the model sees placeholders, but its reply has real values restored before being returned to the client.

### Custom patterns and allowlist

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-pii-sanitizer": {
        "categories": ["email"],
        "allowlist": ["support@company.com"],
        "custom_patterns": [
          { "name": "emp_id", "pattern": "EMP-\\d{6}", "replace_with": "[EMP_ID]" }
        ]
      }
    }
  }'
```

### Block when PII is detected

```json
{
  "ai-pii-sanitizer": {
    "direction": "input",
    "action": "block",
    "categories": ["credit_card", "us_ssn"],
    "on_block": { "status": 403, "body": "PII detected, request blocked" }
  }
}
```

## Delete the Plugin

To remove the Plugin, delete it from the Route's plugin list:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "ai-pii-sanitizer": null
    }
  }'
```
