---
title: jwe-decrypt
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - JWE Decrypt
  - jwe-decrypt
description: This document contains information about the Apache APISIX jwe-decrypt Plugin.
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

The `jwe-decrypt` Plugin is used to decrypt [JWE](https://datatracker.ietf.org/doc/html/rfc7516) authentication header to a [Service](../terminology/service.md) or a [Route](../terminology/route.md).

A [Consumer](../terminology/consumer.md) of the service then needs to provide a key decrypt the request.

## Attributes

For Consumer:

| Name          | Type    | Required                                              | Default | Valid values                | Description                                                                                                                                                                                 |
|---------------|---------|-------------------------------------------------------|---------|-----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | True                                                  |         |                             | Unique key for a Consumer.                                                                                                                                                                  |
| secret        | string  | True                                                 |         |                             | The decrypt key. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.       |
|  is_base64_encoded | boolean | False                                                 | false   |                             | Set to true if the secret is base64 encoded.                                                                                                                                                |

For Route:

| Name   | Type   | Required | Default       | Description                                                         |
|--------|--------|----------|---------------|---------------------------------------------------------------------|
| header | string | False    | authorization | The header to get the token from.                                   |
| forward_header | string | False     | authorization  | Set the header name pass the plaintext to the Upstream.   |

## API

This Plugin adds `/apisix/plugin/jwe/encrypt` as an endpoint.

:::note

You may need to use the [public-api](public-api.md) plugin to expose this endpoint.

:::

## Enable Plugin

To enable the Plugin, you have to create a Consumer object with the JWE token and configure your Route to use JWE authentication.

First, you can create a Consumer object through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwe-decrypt": {
            "key": "user-key",
            "secret": "keylength-must-32byte-are-you-ok"
        }
    }
}'
```

:::note

Once you have created a Consumer object, you can configure a Route to decrypt the header:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything*",
    "plugins": {
        "jwe-decrypt": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```

:::

## Example usage

You need to first setup a Route for an API that signs the token using the [public-api](public-api.md) Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/jwenew -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/apisix/plugin/jwe/encrypt",
    "plugins": {
        "public-api": {}
    }
}'
```

Now, we can get a token:

```shell
curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' 'http://127.0.0.1:9080/apisix/plugin/jwe/encrypt?key=user-key' -i
```

```
HTTP/1.1 200 OK
Date: Mon, 25 Sep 2023 02:38:16 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.5.0
Apisix-Plugins: public-api

eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.hfzMJ0YfmbMcJ0ojgv4PYAHxPjlgMivmv35MiA.7nilnBt2dxLR_O6kf-HQUA
```

You can now use this token while making requests:

```shell
curl http://127.0.0.1:9080/anything/hello -H 'Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.hfzMJ0YfmbMcJ0ojgv4PYAHxPjlgMivmv35MiA.7nilnBt2dxLR_O6kf-HQUA' -i
```

You can see header "Authorization" change to plaintext.

```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 452
Connection: keep-alive
Date: Mon, 25 Sep 2023 02:38:59 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.5.0
Apisix-Plugins: jwe-decrypt

{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "{\"uid\":10000,\"uname\":\"test\"}",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.1.2",
    "X-Amzn-Trace-Id": "Root=1-6510f2c3-1586ec011a22b5094dbe1896",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 119.143.79.94",
  "url": "http://127.0.0.1/anything/hello"
}
```

## Delete Plugin

To remove the `jwe-decrypt` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```
