---
title: request-id
keywords:
  - Apache APISIX
  - API Gateway
  - Request ID
description: The request-id Plugin adds a unique ID to each request proxied through APISIX, which can be used to track API requests.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/request-id" />
</head>

## Description

The `request-id` Plugin adds a unique ID to each request proxied through APISIX, which can be used to track API requests. If a request carries an ID in the header and is not empty ("") corresponding to `header_name`, the Plugin will use the header value as the unique ID and will not overwrite with the automatically generated ID.

## Attributes

| Name                | Type    | Required | Default        | Valid values                    | Description                                                            |
| ------------------- | ------- | -------- | -------------- | ------------------------------- | ---------------------------------------------------------------------- |
| header_name         | string  | False    | "X-Request-Id" |                                 | Name of the header that carries the request unique ID. Note that if a request carries an ID in the `header_name` header, the Plugin will use the header value as the unique ID and will not overwrite it with the generated ID.                                 |
| include_in_response | boolean | False    | true           |                                 | If true, include the generated request ID in the response header, where the name of the header is the `header_name` value. |
| algorithm           | string  | False    | "uuid"         | ["uuid","nanoid","range_id","ksuid"] | Algorithm used for generating the unique ID. When set to `uuid` , the Plugin generates a universally unique identifier. When set to `nanoid`, the Plugin generates a compact, URL-safe ID. When set to `range_id`, the Plugin generates a sequential ID with specific parameters. When set to `ksuid`, the Plugin generates a sequential ID with timestamp and random number.                  |
| range_id      | object | False | |   | Configuration for generating a request ID using the `range_id` algorithm.  |
| range_id.char_set      | string | False | "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789" | minimum length 6 | Character set used for the `range_id` algorithm. |
| range_id.length    | integer | False | 16             | >=6 | Length of the generated ID for the `range_id` algorithm. |

## Examples

The examples below demonstrate how you can configure `request-id` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Attach Request ID to Default Response Header

The following example demonstrates how to configure `request-id` on a Route which attaches a generated request ID to the default `X-Request-Id` response header, if the header value is not passed in the request. When the `X-Request-Id` header is set in the request, the Plugin will take the value in the request header as the request ID.

Create a Route with the `request-id` Plugin using its default configurations (explicitly defined):

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Request-Id",
        "include_in_response": true,
        "algorithm": "uuid"
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Request-Id` header with a generated ID:

```text
X-Request-Id: b9b2c0d4-d058-46fa-bafc-dd91a0ccf441
```

Send a request to the Route with a empty request ID in the header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'X-Request-Id;'
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Request-Id` header with a generated ID:

```text
X-Request-Id: b9b2c0d4-d058-46fa-bafc-dd91a0ccf441
```

Send a request to the Route with a custom request ID in the header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'X-Request-Id: some-custom-request-id'
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Request-Id` header with the custom request ID:

```text
X-Request-Id: some-custom-request-id
```

### Attach Request ID to Custom Response Header

The following example demonstrates how to configure `request-id` on a Route which attaches a generated request ID to a specified header.

Create a Route with the `request-id` Plugin to define a custom header that carries the request ID and include the request ID in the response header:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Req-Identifier",
        "include_in_response": true
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

Send a request to the route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Req-Identifier` header with a generated ID:

```text
X-Req-Identifier: 1c42ff59-ee4c-4103-a980-8359f4135b21
```

### Hide Request ID in Response Header

The following example demonstrates how to configure `request-id` on a Route which attaches a generated request ID to a specified header. The header containing the request ID should be forwarded to the Upstream service but not returned in the response header.

Create a Route with the `request-id` Plugin to define a custom header that carries the request ID and not include the request ID in the response header:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Req-Identifier",
        "include_in_response": false
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response not and see `X-Req-Identifier` header among the response headers. In the response body, you should see:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-6752748c-7d364f48564508db1e8c9ea8",
    "X-Forwarded-Host": "127.0.0.1",
    "X-Req-Identifier": "268092bc-15e1-4461-b277-bf7775f2856f"
  },
  ...
}
```

This shows the request ID is forwarded to the Upstream service but not returned in the response header.

### Use `nanoid` Algorithm

The following example demonstrates how to configure `request-id` on a Route and use the `nanoid` algorithm to generate the request ID.

Create a Route with the `request-id` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "algorithm": "nanoid"
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Req-Identifier` header with an ID generated using the `nanoid` algorithm:

```text
X-Request-Id: kepgHWCH2ycQ6JknQKrX2
```

### Use `ksuid` Algorithm

The following example demonstrates how to configure `request-id` on a Route and use the `ksuid` algorithm to generate the request ID.

Create a Route with the `request-id` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "algorithm": "ksuid"
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the `X-Request-Id` header with an ID generated using the `ksuid` algorithm:

```text
X-Request-Id: 325ghCANEKjw6Jsfejg5p6QrLYB
```

If the [ksuid](https://github.com/segmentio/ksuid?tab=readme-ov-file#command-line-tool) is installed, this ID can be viewed through `ksuid -f inspect 325ghCANEKjw6Jsfejg5p6QrLYB`:

``` text
REPRESENTATION:

    String: 325ghCANEKjw6Jsfejg5p6QrLYB
    Raw: 15430DBBD7F68AD7CA0AE277772AB36DDB1A3C13

COMPONENTS:

    Time: 2025-09-01 16:39:23 +0800 CST
    Timestamp: 356715963
    Payload: D7F68AD7CA0AE277772AB36DDB1A3C13
```

### Attach Request ID Globally and on a Route

The following example demonstrates how to configure `request-id` as a global Plugin and on a Route to attach two IDs.

Create a global rule for the `request-id` Plugin which adds request ID to a custom header:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/global_rules" -X PUT -d '{
  "id": "rule-for-request-id",
  "plugins": {
    "request-id": {
      "header_name": "Global-Request-ID"
    }
  }
}'
```

Create a Route with the `request-id` Plugin which adds request ID to a different custom header:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "Route-Request-ID"
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the response includes the following headers:

```text
Global-Request-ID: 2e9b99c1-08ed-4a74-b347-49c0891b07ad
Route-Request-ID: d755666b-732c-4f0e-a30e-a7a71ace4e26
```
