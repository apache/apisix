---
title: data-mask
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - data-mask
description: This document contains information about the Apache APISIX data-mask Plugin.
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

The `data-mask` Plugin masks or redacts sensitive fields in request data — query parameters, headers, and body — before they appear in access logs or logger plugins (such as `file-logger` or `http-logger`).

This is useful for preventing credentials, tokens, payment card numbers, and other sensitive information from being written to logs.

The plugin runs in the `log` phase and supports three masking actions:

- `remove`: completely removes the field from the request data.
- `replace`: replaces the field value with a fixed string.
- `regex`: applies a regular expression substitution to the field value.

## Attributes

| Name                | Type    | Required | Default   | Description                                                                    |
|---------------------|---------|----------|-----------|--------------------------------------------------------------------------------|
| request             | array   | False    |           | List of masking rules to apply to request data.                                |
| max_body_size       | integer | False    | 1048576   | Maximum request body size in bytes to process. Bodies larger than this value are skipped for body masking. |
| max_req_post_args   | integer | False    | 100       | Maximum number of URL-encoded form fields to parse when masking `urlencoded` body data. |

Each object in the `request` array has the following fields:

| Name          | Type   | Required                                  | Description                                                                                                         |
|---------------|--------|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| type          | string | True                                      | Type of request data to mask. One of `query`, `header`, or `body`.                                                 |
| name          | string | True                                      | Field name to mask. For `query` and `header` types, this is the parameter or header name. For `body` type with `body_format: json`, this is a [JSONPath](https://goessner.net/articles/JsonPath/) expression. |
| action        | string | True                                      | Masking action to apply. One of `remove`, `replace`, or `regex`.                                                   |
| body_format   | string | Required when `type` is `body`            | Format of the request body. One of `json` or `urlencoded`.                                                         |
| regex         | string | Required when `action` is `regex`         | Regular expression pattern to match against the field value. Capture groups can be referenced in `value` as `$1`, `$2`, etc. |
| value         | string | Required when `action` is `replace` or `regex` | Replacement value. When used with `action: regex`, capture groups from `regex` can be referenced as `$1`, `$2`, etc. |

## Examples

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Mask query parameters

The following example creates a route with `data-mask` configured to mask query parameters. The `password` parameter is removed entirely, `token` is replaced with a fixed string, and the `card` number is partially masked using a regex.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "query",
          "name": "password",
          "action": "remove"
        },
        {
          "type": "query",
          "name": "token",
          "action": "replace",
          "value": "*****"
        },
        {
          "type": "query",
          "name": "card",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "path": "logs/access.log"
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

Send a request with sensitive query parameters:

```shell
curl "http://127.0.0.1:9080/anything?password=secret&token=mytoken&card=1234-5678-9012-3456"
```

In `logs/access.log`, the logged request URI will have the sensitive fields masked:

```
/anything?token=*****&card=1234-****-****-3456
```

The `password` parameter is absent, `token` is replaced with `*****`, and only the first and last four digits of the card number are preserved.

### Mask request headers

The following example masks sensitive request headers. The `Authorization` header is removed, `X-API-Key` is replaced with a fixed string, and a custom `X-Card-Number` header is partially masked using a regex.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "header",
          "name": "Authorization",
          "action": "remove"
        },
        {
          "type": "header",
          "name": "X-API-Key",
          "action": "replace",
          "value": "[REDACTED]"
        },
        {
          "type": "header",
          "name": "X-Card-Number",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "path": "logs/access.log"
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

Send a request with sensitive headers:

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Authorization: Bearer secret-token" \
  -H "X-API-Key: my-api-key" \
  -H "X-Card-Number: 1234-5678-9012-3456"
```

In `logs/access.log`, the logged request headers will have the sensitive values masked.

### Mask JSON body fields using JSONPath

The following example masks fields in a JSON request body. It removes the top-level `password` field, replaces the `token` field of every element in the `users` array, and applies a regex to the nested `credit.card` field of each user.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "body",
          "body_format": "json",
          "name": "$.password",
          "action": "remove"
        },
        {
          "type": "body",
          "body_format": "json",
          "name": "$.users[*].token",
          "action": "replace",
          "value": "*****"
        },
        {
          "type": "body",
          "body_format": "json",
          "name": "$.users[*].credit.card",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "include_req_body": true,
      "path": "logs/access.log"
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

Send a request with a JSON body containing sensitive fields:

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Content-Type: application/json" \
  -d '{
    "password": "secret",
    "users": [
      {
        "name": "alice",
        "token": "tok_abc123",
        "credit": { "card": "1234-5678-9012-3456" }
      },
      {
        "name": "bob",
        "token": "tok_xyz789",
        "credit": { "card": "9876-5432-1098-7654" }
      }
    ]
  }'
```

In `logs/access.log`, the logged request body will have the sensitive fields masked:

```json
{
  "users": [
    {
      "name": "alice",
      "token": "*****",
      "credit": { "card": "1234-****-****-3456" }
    },
    {
      "name": "bob",
      "token": "*****",
      "credit": { "card": "9876-****-****-7654" }
    }
  ]
}
```

The `password` field is absent, all `token` fields are replaced with `*****`, and card numbers are partially masked.

## Delete Plugin

To remove the `data-mask` Plugin, delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```
