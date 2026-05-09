---
title: oas-validator
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - oas-validator
  - OpenAPI
  - request validation
description: The oas-validator Plugin validates incoming HTTP requests against an OpenAPI Specification (OAS) 3.x document, rejecting non-conforming requests before they reach the upstream service.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/oas-validator" />
</head>

## Description

The `oas-validator` Plugin validates incoming HTTP requests against an [OpenAPI Specification (OAS) 3.x](https://swagger.io/specification/) document before forwarding them to the upstream service. It can validate the request method, path, query parameters, request headers, and body.

The OpenAPI spec can be provided as an inline JSON string or fetched from a remote URL with configurable caching. Validation failures return a configurable HTTP error status, and detailed error messages can optionally be included in the response body.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| spec | string | No* | | | Inline OpenAPI 3.x specification in JSON format. Required if `spec_url` is not set. |
| spec_url | string | No* | | `^https?://` | URL to fetch the OpenAPI specification from. Required if `spec` is not set. |
| spec_url_request_headers | object | No | | | Custom HTTP request headers sent when fetching `spec_url`. Useful for authenticated specification endpoints. |
| ssl_verify | boolean | No | false | | Whether to verify the TLS certificate when fetching `spec_url`. |
| timeout | integer | No | 10000 | [1000, 60000] | HTTP request timeout in milliseconds for fetching `spec_url`. |
| verbose_errors | boolean | No | false | | When `true`, include detailed validation error messages in the response body. |
| skip_request_body_validation | boolean | No | false | | Skip validation of the request body. |
| skip_request_header_validation | boolean | No | false | | Skip validation of request headers. |
| skip_query_param_validation | boolean | No | false | | Skip validation of query string parameters. |
| skip_path_params_validation | boolean | No | false | | Skip validation of path parameters. |
| reject_if_not_match | boolean | No | true | | When `true`, reject requests that fail validation. When `false`, log the validation failure and allow the request through. |
| rejection_status_code | integer | No | 400 | [400, 599] | HTTP status code to return when a request fails validation. |

\* Exactly one of `spec` or `spec_url` must be provided.

### Plugin Metadata

The following metadata attributes control behavior at the plugin level and are configured through the Plugin Metadata API:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| spec_url_ttl | integer | No | 3600 | ≥ 1 | Time in seconds to cache a specification fetched from `spec_url`. |

## Examples

The examples below demonstrate how you can configure `oas-validator` in different scenarios.

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Validate Requests with an Inline Specification

The following example demonstrates how to validate requests against an inline OpenAPI 3.x specification. Requests that do not conform to the spec are rejected with a `400` response.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "oas-validator-route",
    "uri": "/api/v3/*",
    "plugins": {
      "oas-validator": {
        "spec": "{\"openapi\":\"3.0.2\",\"info\":{\"title\":\"Pet API\",\"version\":\"1.0.0\"},\"paths\":{\"/api/v3/pet\":{\"post\":{\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"status\":{\"type\":\"string\"}}}}}},\"responses\":{\"200\":{\"description\":\"OK\"}}}}}}",
        "verbose_errors": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

Send a valid request with the required `name` field:

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "doggie", "status": "available"}'
```

You should receive a `200` response from the upstream.

Send an invalid request without the required `name` field:

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"status": "available"}'
```

You should receive a `400` response with a validation error message.

### Validate Requests with a Remote Specification URL

The following example demonstrates how to fetch the OpenAPI specification from a remote URL. The spec is fetched once and cached for the duration specified by `spec_url_ttl` in the plugin metadata.

Configure the plugin metadata to set the cache TTL for the remote spec:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/oas-validator" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "spec_url_ttl": 600
  }'
```

Create a Route with the `oas-validator` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "oas-validator-url-route",
    "uri": "/api/v3/*",
    "plugins": {
      "oas-validator": {
        "spec_url": "https://petstore3.swagger.io/api/v3/openapi.json",
        "ssl_verify": false,
        "verbose_errors": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

Send a request that does not conform to the Petstore spec:

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"invalid": "body"}'
```

You should receive a `400` response with a detailed validation error message because `verbose_errors` is set to `true`.
