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

The `jwe-decrypt` Plugin is used to decrypt [JWE](https://datatracker.ietf.org/doc/html/rfc7516) authorization headers in requests to an APISIX [Service](../terminology/service.md) or [Route](../terminology/route.md).

This Plugin adds an endpoint `/apisix/plugin/jwe/encrypt` for JWE encryption. For decryption, the key should be configured in [Consumer](../terminology/consumer.md).

## Attributes

For Consumer:

| Name          | Type    | Required                                              | Default | Valid values                | Description                                                                                                                                  |
|---------------|---------|-------------------------------------------------------|---------|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | True                                                  |         |                             | Unique key for a Consumer.                                                                                                                   |
| secret        | string  | True                                                 |         |                             | The decryption key. Must be 32 characters. The key could be saved in a secret manager using the [Secret](../terminology/secret.md) resource. |
| is_base64_encoded | boolean | False                                                 | false   |                             | Set to true if the secret is base64 encoded.                                                                                                 |

:::note

After enabling `is_base64_encoded`, your `secret` length may exceed 32 chars. You only need to make sure that the length after decoding is still 32 chars.

:::

For Route:

| Name   | Type   | Required | Default       | Description                                                         |
|--------|--------|----------|---------------|---------------------------------------------------------------------|
| header | string | True    | Authorization | The header to get the token from.                                   |
| forward_header | string | True     | Authorization  | Set the header name that passes the plaintext to the Upstream.   |
| strict | boolean | False     | true  | If true, throw a 403 error if JWE token is missing from the request. If false, do not throw an error if JWE token cannot be found.  |

## Example usage

First, create a Consumer with `jwe-decrypt` and configure the decryption key:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwe-decrypt": {
            "key": "user-key",
            "secret": "-secret-length-must-be-32-chars-"
        }
    }
}'
```

Next, create a Route with `jwe-decrypt` enabled to decrypt the authorization header:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

### Encrypt Data with JWE

The Plugin creates an internal endpoint `/apisix/plugin/jwe/encrypt` to encrypt data with JWE. To expose it publicly, create a Route with the [public-api](public-api.md) Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/jwenew -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/apisix/plugin/jwe/encrypt",
    "plugins": {
        "public-api": {}
    }
}'
```

Send a request to the endpoint passing the key configured in Consumer to the URI parameter to encrypt some sample data in the payload:

```shell
curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' 'http://127.0.0.1:9080/apisix/plugin/jwe/encrypt?key=user-key' -i
```

You should see a response similar to the following, with the JWE encrypted data in the response body:

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

### Decrypt Data with JWE

Send a request to the route with the JWE encrypted data in the `Authorization` header:

```shell
curl http://127.0.0.1:9080/anything/hello -H 'Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.hfzMJ0YfmbMcJ0ojgv4PYAHxPjlgMivmv35MiA.7nilnBt2dxLR_O6kf-HQUA' -i
```

You should see a response similar to the following, where the `Authorization` header shows the plaintext of the payload:

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
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
