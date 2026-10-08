---
title: request-decompress
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - REQUEST DECOMPRESS
  - request-decompress
description: The request-decompress Plugin decompresses a request body sent with a Content-Encoding of gzip or deflate, so that the other Plugins on the Route and, optionally, the Upstream receive the plain body.
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

The `request-decompress` Plugin decompresses a request body sent with a `Content-Encoding` of `gzip` or `deflate`, which [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#section-8.4) allows, and rewrites the request with the plain body. Every Plugin that runs after it reads the decompressed content, so `oas-validator`, `request-validation`, `body-transformer`, `chaitin-waf` and the logging Plugins work on a compressed request the same way they do on a plain one.

A request without a `Content-Encoding` header passes through untouched and its body is never read, so the same Route serves both compressed and uncompressed clients.

A gzip body may carry several members concatenated, which [RFC 1952 section 2.2](https://www.rfc-editor.org/rfc/rfc1952#section-2.2) allows. Every member is decompressed and `max_req_body_size` bounds their total.

By default the Upstream also receives the decompressed body and the `Content-Encoding` header is removed. Set `forward_compressed` to `true` to send a compressed body Upstream instead, while the Plugins on the Route still read the plain one.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
| ---- | ---- | -------- | ------- | ------------ | ----------- |
| max_req_body_size | integer | False | 1048576 | >= 1 | Maximum size in bytes of the request body, applied both to the body as it arrives and to the decompressed result. A body beyond this size is rejected with a `413`. The limit is applied while decompressing, so an oversized payload is never buffered in full. |
| forward_compressed | boolean | False | false | | If true, the Upstream receives a compressed body instead of the decompressed one. |

## Rejections

| Condition | Status | Notes |
| --------- | ------ | ----- |
| A coding other than `gzip`, `deflate` or `identity`, such as `br` | `415` | The response carries an `Accept-Encoding: gzip, deflate` header, as [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#section-12.5.3) recommends. |
| A malformed compressed body, or bytes trailing the last gzip member | `400` | |
| A body beyond `max_req_body_size`, as received or once decompressed | `413` | |

## Examples

The examples below demonstrate how you can configure `request-decompress` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Decompress a request body

The following example demonstrates how to decompress a gzip request body and forward the plain body to the Upstream.

Create a Route with the `request-decompress` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-decompress-route",
    "uri": "/anything",
    "plugins": {
      "request-decompress": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a gzip compressed body to the Route:

```shell
echo -n '{"name":"world"}' | gzip | curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  --data-binary @-
```

You should see a response showing that the Upstream received the plain body and no `Content-Encoding` header:

```json
{
  "data": "{\"name\":\"world\"}",
  "headers": {
    "Content-Type": "application/json",
    ...
  },
  ...
}
```

### Validate a compressed request body against an OpenAPI specification

The following example demonstrates how to validate the decompressed body with the [`oas-validator`](./oas-validator.md) Plugin, so that an invalid request is rejected before it reaches the Upstream.

Create a Route with both Plugins:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-decompress-route",
    "uri": "/anything",
    "plugins": {
      "request-decompress": {},
      "oas-validator": {
        "spec": "{\"openapi\":\"3.0.2\",\"info\":{\"title\":\"test\",\"version\":\"1.0\"},\"paths\":{\"/anything\":{\"post\":{\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"}}}}}},\"responses\":{\"200\":{\"description\":\"ok\"}}}}}}"
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

Send a gzip compressed body that does not match the specification:

```shell
echo -n '{"nickname":"world"}' | gzip | curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  --data-binary @-
```

You should receive an `HTTP/1.1 400 Bad Request` response, showing that the specification was checked against the decompressed body.

### Forward a compressed body to the Upstream

The following example demonstrates how to keep the Upstream receiving a compressed body while the Plugins on the Route still read the plain one.

Create a Route with `forward_compressed` enabled:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-decompress-route",
    "uri": "/anything",
    "plugins": {
      "request-decompress": {
        "forward_compressed": true
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

Send a gzip compressed body to the Route:

```shell
echo -n '{"name":"world"}' | gzip | curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  --data-binary @-
```

The Upstream receives the body still compressed, with the `Content-Encoding` header restored. When no Plugin modified the body, the bytes are forwarded exactly as the client sent them. When a Plugin such as `body-transformer` rewrote the body, it is compressed again with the coding the client used, and the header names the coding that was applied.

## Plugin order

`request-decompress` runs in the `rewrite` phase with a priority of `2850`. That places it after the Plugins that reject a request cheaply, so a blocked request is never decompressed, and before every Plugin that reads the request body.

A Route that configures the Plugin takes precedence over a Global Rule that also configures it, so the request body is handled once with the Route's settings.

Two consequences are worth knowing, and both can be changed with [`_meta.priority`](../terminology/plugin.md#plugins-execution-order):

- `hmac-auth` with `validate_request_body` enabled hashes the decompressed body on a Route that also enables this Plugin. A client that signs the compressed bytes needs `hmac-auth` configured with a priority above `2850`.
- Decompression happens before authentication, so an unauthenticated client can cause decompression work. It is bounded by `max_req_body_size` and by `client_max_body_size`.
