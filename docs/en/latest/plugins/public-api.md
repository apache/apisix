---
title: public-api
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

The `public-api` plugin is used to enhance the plugin public API access control.
When current users develop custom plugins, they can register some public APIs for fixed functionality, such as the `/apisix/plugin/jwt/sign` API in `jwt-auth`. These APIs can only apply limited plugins for access control (currently only `ip-restriction`) by way of plugin interceptors.

With the `public-api` plugin, we put all public APIs into the general HTTP API router, which is consistent with the normal Route registered by the user and can apply any plugin. The public API added in the user plugin is no longer expose by default by APISIX, and the user has to manually configure the Route for it, the user can configure any uri and plugin.

## Attributes

| Name | Type | Requirement | Default | Valid | Description |
| -- | -- | -- | -- | -- | -- |
| uri | string | optional | "" |   | The uri of the public API. When you set up the route, you can use this to configure the original API uri if it is used in a way that is inconsistent with the original public API uri. |

## Example

We take the `jwt-auth` token sign API as an example to show how to configure the `public-api` plugin. Also, the `key-auth` will be used to show how to configure the protection plugin for the public API.

### Prerequisites

The use of key-auth and jwt-auth requires the configuration of a consumer that contains the configuration of these plugins, and you need to create one in advance, the process will be omitted here.

### Basic Use Case

First we will setup a route.

```shell
$ curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/apisix/plugin/jwt/sign",
    "plugins": {
        "public-api": {}
    }
}'
```

Let's test it.

```shell
$ curl 'http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key'
```

It will respond to a text JWT.

### Customize URI

Let's setup another route.

```shell
$ curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        }
    }
}'
```

Let's test it.

```shell
$ curl 'http://127.0.0.1:9080/gen_token?key=user-key'
```

It will still respond to a text JWT. We can see that users are free to configure URI for the public API to match.

### Protect Route

Let's modify the last route and add `key-auth` authentication to it.

```shell
$ curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        },
        "key-auth": {}
    }
}'
```

Let's test it.

```shell
$ curl -i 'http://127.0.0.1:9080/gen_token?key=user-key'
    -H "apikey: test-apikey"
HTTP/1.1 200 OK

# Failed request
$ curl -i 'http://127.0.0.1:9080/gen_token?key=user-key'
HTTP/1.1 401 UNAUTHORIZED
```

It will still respond to a text JWT. If we don't add `apikey` to the request header, it will respond with a 401 block request. In this way, we have implemented a plugin approach to protect the public API.
