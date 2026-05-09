---
title: acl
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - acl
description: The acl Plugin implements label-based access control for API routes, allowing or denying requests based on consumer labels or external user attributes.
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `acl` Plugin provides label-based access control for API routes. It checks consumer labels (from APISIX [Consumers](../terminology/consumer.md)) or external user attributes (from authentication plugins that set `ctx.external_user`) against configured allow or deny lists.

The Plugin supports three label value formats:

- **table**: the label value is a Lua table (array).
- **json**: the label value is a JSON-encoded array string, e.g. `["admin","user"]`.
- **segmented_text**: the label value is a delimiter-separated string, e.g. `admin,user`.

At least one of `allow_labels` or `deny_labels` must be configured. When both are present, `deny_labels` is evaluated first.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| allow_labels | object | False* | | | Labels to allow. Keys are label names, values are arrays of allowed label values. At least one of `allow_labels` or `deny_labels` must be configured. |
| deny_labels | object | False* | | | Labels to deny. Keys are label names, values are arrays of denied label values. At least one of `allow_labels` or `deny_labels` must be configured. |
| rejected_code | integer | False | 403 | >= 200 | HTTP status code returned when the request is rejected. |
| rejected_msg | string | False | | | Custom rejection message body. If not set, defaults to `{"message":"The consumer is forbidden."}`. |
| external_user_label_field | string | False | `groups` | | JSONPath expression used to extract the label value from `ctx.external_user`. |
| external_user_label_field_key | string | False | | | The label key name used for the extracted value. Defaults to the value of `external_user_label_field`. |
| external_user_label_field_parser | string | False | | `segmented_text`, `json`, `table` | How to parse the extracted field value. If not set, the Plugin auto-detects the format. |
| external_user_label_field_separator | string | False | | | Separator regex for the `segmented_text` parser. Required when `external_user_label_field_parser` is `segmented_text`. |

## Examples

The examples below demonstrate how you can configure the `acl` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Allow Consumers by Label

The example below demonstrates how to use the `acl` Plugin with [`key-auth`](./key-auth.md) to allow only consumers that have a specific label value.

Create a Consumer `alice` with a label `team: platform`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "alice",
    "plugins": {
      "key-auth": {
        "key": "alice-key"
      }
    },
    "labels": {
      "team": "platform"
    }
  }'
```

Create a second Consumer `bob` with a different label `team: sales`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "bob",
    "plugins": {
      "key-auth": {
        "key": "bob-key"
      }
    },
    "labels": {
      "team": "sales"
    }
  }'
```

Create a Route with `key-auth` and `acl` configured to allow only consumers with label `team: platform`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-allow-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "allow_labels": {
          "team": ["platform"]
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

Send a request as `alice` (label `team: platform`):

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: alice-key"
```

You should receive an HTTP `200` response, as `alice` has the allowed label.

Send a request as `bob` (label `team: sales`):

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: bob-key"
```

You should receive an HTTP `403` response, as `bob` does not have the allowed label.

### Deny Consumers by Label

The example below demonstrates how to block consumers based on a label value while allowing all others.

Create a Consumer `carol` with label `role: guest`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "carol",
    "plugins": {
      "key-auth": {
        "key": "carol-key"
      }
    },
    "labels": {
      "role": "guest"
    }
  }'
```

Create a Route that denies consumers with label `role: guest`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-deny-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "deny_labels": {
          "role": ["guest"]
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

Send a request as `carol`:

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: carol-key"
```

You should receive an HTTP `403` response.

### Custom Rejection Code and Message

You can customize the HTTP status code and message returned when access is denied.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-custom-reject-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "allow_labels": {
          "team": ["platform"]
        },
        "rejected_code": 401,
        "rejected_msg": "Access denied: insufficient label permissions."
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

When a Consumer without the required label accesses the route, they receive a `401` response with the configured message.
