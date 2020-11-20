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

- [中文](../zh-cn/plugins/jwt-auth.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`jwt-auth` is an authentication plugin that need to work with `consumer`. Add JWT Authentication to a `service` or `route`.

The `consumer` then adds its key to the query string parameter, request header, or `cookie` to verify its request.

For more information on JWT, refer to [JWT](https://jwt.io/) for more information.

## Attributes

| Name          | Type    | Requirement | Default | Valid                       | Description                                                                                                                                      |
|:--------------|:--------|:------------|:--------|:----------------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | required    |         |                             | different `consumer` have different value, it's unique. different `consumer` use the same `key`, and there will be a request matching exception. |
| secret        | string  | optional    |         |                             | encryption key. if you do not specify, the value is auto-generated in the background.                                                            |
| public_key    | string  | optional    |         |                             | RSA public key, required when `algorithm` attribute selects `RS256` algorithm.                                                                   |
| private_key   | string  | optional    |         |                             | RSA private key, required when `algorithm` attribute selects `RS256` algorithm.                                                                  |
| algorithm     | string  | optional    | "HS256" | ["HS256", "HS512", "RS256"] | encryption algorithm.                                                                                                                            |
| exp           | integer | optional    | 86400   | [1,...]                     | token's expire time, in seconds                                                                                                                  |
| base64_secret | boolean | optional    | false   |                             | whether secret is base64 encoded                                                                                                                 |

## API

This plugin will add `/apisix/plugin/jwt/sign` to sign.
You may need to use [interceptors](../plugin-interceptors.md) to protect it.

## How To Enable

1. set a consumer and config the value of the `jwt-auth` option

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "secret": "my-secret-key"
        }
    }
}'
```

`jwt-auth` uses the `HS256` algorithm by default, and if you use the `RS256` algorithm, you need to specify the algorithm and configure the public key and private key, as follows:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "kerouac",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----",
            "private_key": "-----BEGIN RSA PRIVATE KEY-----\n……\n-----END RSA PRIVATE KEY-----",
            "algorithm": "RS256"
        }
    }
}'
```

you can visit Dashboard `http://127.0.0.1:9080/apisix/dashboard/` and add a Consumer through the web console:

![](../images/plugin/jwt-auth-1.png)

then add jwt-auth plugin in the Consumer page:
![](../images/plugin/jwt-auth-2.png)

2. add a Route or add a Service, and enable the `jwt-auth` plugin

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "jwt-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

## Test Plugin

#### get the token in `jwt-auth` plugin:

```shell
$ curl http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI
```

#### try request with token

* without token:

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

* request header with token:

```shell
$ curl http://127.0.0.1:9080/index.html -H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* request params with token:

```shell
$ curl http://127.0.0.1:9080/index.html?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* request cookie with token:

```shell
$ curl http://127.0.0.1:9080/index.html --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

## Disable Plugin

When you want to disable the `jwt-auth` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

