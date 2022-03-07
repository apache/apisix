---
title: forward-auth
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

The `forward-auth` plugin implements a classic external authentication model. We can implement a custom error return or user redirection to the authentication page if the authentication fails.

Forward Auth cleverly moves the authentication and authorization logic to a dedicated external service, where the gateway forwards the user's request to the authentication service and blocks the original request, and replaces the result when the authentication service responds with a non-2xx status.

## Attributes

| Name | Type | Requirement | Default | Valid | Description |
| -- | -- | -- | -- | -- | -- |
| uri | string | required |  |  | Authorization service uri (eg. https://localhost/auth) |
| ssl_verify | boolean | optional | true |   | Whether to verify the certificate |
| request_headers | array[string] | optional |  |  | `client` request header that will be sent to the `authorization` service. When it is not set, no `client` request headers are sent to the `authorization` service, except for those provided by APISIX (X-Forwarded-XXX). |
| upstream_headers | array[string] | optional |  |  | `authorization` service response header that will be sent to the `upstream`. When it is not set, will not forward the `authorization` service response header to the `upstream`. |
| client_headers | array[string] | optional |  |  | `authorization` response header that will be sent to the `client` when authorize failure. When it is not set, will not forward the `authorization` service response header to the `client`. |
| timeout | integer | optional | 3000ms | [1, 60000]ms | Authorization service HTTP call timeout |
| keepalive | boolean | optional | true |  | HTTP keepalive |
| keepalive_timeout | integer | optional | 60000ms | [1000, ...]ms | keepalive idle timeout |
| keepalive_pool | integer | optional | 5 | [1, ...]ms | Connection pool limit |

## Data Definition

The request headers in the following list will have APISIX generated and sent to the `authorization` service.

| Scheme | HTTP Method | Host | URI | Source IP |
| -- | -- | -- | -- | -- |
| X-Forwarded-Proto | X-Forwarded-Method | X-Forwarded-Host | X-Forwarded-Uri | X-Forwarded-For |

## Example

First, you need to setup an external authorization service. Here is an example of using Apache APISIX's serverless plugin to mock.

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/auth' \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/auth",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": [
                "return function (conf, ctx)
                    local core = require(\"apisix.core\");
                    local authorization = core.request.header(ctx, \"Authorization\");
                    if authorization == \"123\" then
                        core.response.exit(200);
                    elseif authorization == \"321\" then
                        core.response.set_header(\"X-User-ID\", \"i-am-user\");
                        core.response.exit(200);
                    else core.response.set_header(\"Location\", \"http://example.com/auth\");
                        core.response.exit(403);
                    end
                end"
            ]
        }
    }
}'
```

Next, we create a route for testing.

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/1' \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
    -d '{
    "uri": "/headers",
    "plugins": {
        "forward-auth": {
            "uri": "http://127.0.0.1:9080/auth",
            "request_headers": ["Authorization"],
            "upstream_headers": ["X-User-ID"],
            "client_headers": ["Location"]
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    }
}'
```

We can perform the following three tests.

1. **request_headers** Send Authorization header from `client` to `authorization` service

```shell
curl http://127.0.0.1:9080/headers -H 'Authorization: 123'
```

```
{
    "headers": {
        "Authorization": "123",
        "Next": "More-headers"
    }
}
```

2. **upstream_headers** Send `authorization` service response header to the `upstream`

```shell
curl http://127.0.0.1:9080/headers -H 'Authorization: 321'
```

```
{
    "headers": {
        "Authorization": "321",
        "X-User-ID": "i-am-user",
        "Next": "More-headers"
    }
}
```

3. **client_headers** Send `authorization` service response header to `client` when authorizing failed

```shell
curl -i http://127.0.0.1:9080/headers
```

```
HTTP/1.1 403 Forbidden
Location: http://example.com/auth
```

Finally, you can disable the `forward-auth` plugin by removing it from the route.
