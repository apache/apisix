---
title: forward-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Forward Authentication
  - forward-auth
description: This document contains information about the Apache APISIX forward-auth Plugin.
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

The `forward-auth` Plugin implements a classic external authentication model. When authentication fails, you can have a custom error message or redirect the user to an authentication page.

This Plugin moves the authentication and authorization logic to a dedicated external service. APISIX forwards the user's requests to the external service, blocks the original request, and replaces the result when the external service responds with a non 2xx status code.

## Attributes

| Name              | Type          | Required | Default | Valid values   | Description                                                                                                                                                |
| ----------------- | ------------- | -------- | ------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| uri               | string        | True     |         |                | URI of the authorization service.                                                                                                                          |
| ssl_verify        | boolean       | False    | true    |                | When set to `true`, verifies the SSL certificate.                                                                                                          |
| request_method    | string        | False    | GET     | ["GET","POST"] | HTTP method for a client to send requests to the authorization service. When set to `POST` the request body is send to the authorization service. (not recommended. See `extra_headers`)          |
| request_headers   | array[string] | False    |         |                | Client request headers to be sent to the authorization service. If not set, only the headers provided by APISIX are sent (for example, `X-Forwarded-XXX`). |
| extra_headers   |object | False    |         |                | Extra headers to be sent to the authorization service passed in key-value format. The value can be a variable like `$request_uri`, `$post_arg.xyz` |
| upstream_headers  | array[string] | False    |         |                | Authorization service response headers to be forwarded to the Upstream. If not set, no headers are forwarded to the Upstream service.                      |
| client_headers    | array[string] | False    |         |                | Authorization service response headers to be sent to the client when authorization fails. If not set, no headers will be sent to the client.               |
| timeout           | integer       | False    | 3000ms  | [1, 60000]ms   | Timeout for the authorization service HTTP call.                                                                                                           |
| keepalive         | boolean       | False    | true    |                | When set to `true`, keeps the connection alive for multiple requests.                                                                                      |
| keepalive_timeout | integer       | False    | 60000ms | [1000, ...]ms  | Idle time after which the connection is closed.                                                                                                            |
| keepalive_pool    | integer       | False    | 5       | [1, ...]ms     | Connection pool limit.                                                                                                                           |
| allow_degradation | boolean       | False    | false   |                | When set to `true`, allows authentication to be skipped when authentication server is unavailable. |
| status_on_error   | integer       | False    | 403     | [200,...,599]  | Sets the HTTP status that is returned to the client when there is a network error to the authorization service. The default status is “403” (HTTP Forbidden). |

## Data definition

APISIX will generate and send the request headers listed below to the authorization service:

| Scheme            | HTTP Method        | Host             | URI             | Source IP       |
| ----------------- | ------------------ | ---------------- | --------------- | --------------- |
| X-Forwarded-Proto | X-Forwarded-Method | X-Forwarded-Host | X-Forwarded-Uri | X-Forwarded-For |

## Example usage

First, you need to setup your external authorization service. The example below uses Apache APISIX's [serverless](./serverless.md) Plugin to mock the service:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/auth' \
    -H "X-API-KEY: $admin_key" \
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

Now you can configure the `forward-auth` Plugin to a specific Route:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/1' \
    -H "X-API-KEY: $admin_key" \
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

Now if we send the authorization details in the request header:

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

The authorization service response can also be forwarded to the Upstream:

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

When authorization fails, the authorization service can send custom response back to the user:

```shell
curl -i http://127.0.0.1:9080/headers
```

```
HTTP/1.1 403 Forbidden
Location: http://example.com/auth
```

### Using data from POST body to make decision on Authorization service

::: note
When the decision is to be made on the basis of POST body, then it is recommended to use `$post_arg.xyz` with `extra_headers` field and make the decision on Authorization service on basis of headers rather than using POST `request_method` to pass the entire request body to Authorization service.
:::

Create a serverless function on the `/auth` route that checks for the presence of the `tenant_id` header. If present, the route responds with HTTP 200 and sets the `X-User-ID` header to a fixed value `i-am-an-user`. If `tenant_id` is missing, it returns HTTP 400 with an error message.

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/auth' \
    -H "X-API-KEY: $admin_key" \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/auth",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": [
                "return function(conf, ctx)
                 local core = require(\"apisix.core\")
                 if core.request.header(ctx, \"tenant_id\") then
                     core.response.set_header(\"X-User-ID\", \"i-am-an-user\");
                     core.response.exit(200);
                else
                    core.response.exit(400, \"tenant_id is required\")
                end
            end"
            ]
        }
    }
}'
```

Create a route that accepts POST requests and uses the `forward-auth` plugin to call the auth endpoint with the `tenant_id` from the request. The request is forwarded to the upstream service only if the auth check returns 200.

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/1' \
    -H "X-API-KEY: $admin_key" \
    -d '{
    "uri": "/post",
    "methods": ["POST"],
    "plugins": {
        "forward-auth": {
            "uri": "http://127.0.0.1:9080/auth",
            "request_method": "GET",
            "extra_headers": {"tenant_id": "$post_arg.tenant_id"}
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

Send a POST request with the `tenant_id` header:

```shell
curl -i http://127.0.0.1:9080/post -X POST -d '{
   "tenant_id": 123
}'
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```shell
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 491
Connection: keep-alive
Date: Mon, 07 Jul 2025 06:50:39 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.13.0

{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\n   \"tenant_id\": 123\n}": ""
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "23",
    "Content-Type": "application/x-www-form-urlencoded",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.13.0",
    "X-Amzn-Trace-Id": "Root=1-686b6e3f-2fdeff70183e71551f5c5729",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "127.0.0.1, 106.215.83.33",
  "url": "http://127.0.0.1/post"
}

```

Send a POST request without the `tenant_id` header:

```shell
 curl -i http://127.0.0.1:9080/post -X POST -d '{
   "abc": 123
}'


HTTP/1.1 400 Bad Request
Date: Mon, 07 Jul 2025 06:54:04 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.13.0

tenant_id is required
```

## Delete Plugin

To remove the `forward-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
