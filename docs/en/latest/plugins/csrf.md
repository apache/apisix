---
title: csrf
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

## Summary

- [**Description**](#description)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Description

The `CSRF` plugin based on the `Double Submit Cookie` way, protect your API from CSRF attacks.

## Attributes

| Name             | Type    | Requirement | Default | Valid | Description                                                  |
| ---------------- | ------- | ----------- | ------- | ----- | ------------------------------------------------------------ |
|   name   |  string |    false    | `apisix_csrf_token`  |    | The name of the token in the generated cookie. |
| expires |  number | false | `7200` | | Expiration time(s) of csrf cookie. |
| key | string | true |  |  | The secret key used to encrypt the cookie. |

## How To Enable

1. Create the route and enable the plugin.

```
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT-d '
{
  "uri": "/hello",
  "plugins": {
    "csrf": {
      "key": "edd1c9f034335f136f87ad84b625c8f1"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:9001": 1
    }
  }
}'
```

The route is then protected, and if you access it using methods other than `GET`, you will see that the request was blocked and receive a 401 status code back.

2. Using `GET` requests `/hello`, a cookie with an encrypted token is received in the response. Token name is the `name` field set in the plugin configuration, if not set, the default value is `apisix_csrf_token`.

3. In subsequent non-GET requests to this route, you need to read the encrypted token from the cookie and append the token to the `request header`, setting the field name to the `name` in the plugin configuration.

## Test Plugin

The above configuration created a `/hello` route and enabled the csrf plugin, now direct access to the route using a non-GET method will return an error:

```
curl -i http://127.0.0.1:9080/hello -X POST
```

```
HTTP/1.1 401 Unauthorized
Date: Mon, 13 Dec 2021 07:23:23 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX
```

When accessed with a GET request, the correct return and a cookie with an encrypted token are obtained:

```
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 13
Connection: keep-alive
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
permissions-policy: interest-cohort=()
date: Mon, 13 Dec 2021 07:33:55 GMT
Server: APISIX
Set-Cookie: apisix_csrf_token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==;path=/;Expires=Mon, 13-Dec-21 09:33:55 GMT
```

The token needs to be read from the cookie and carried in the request header in subsequent non-GET requests. You also need to make sure that you carry the cookie.

## Disable Plugin

Send a request to update the route to disable the plugin:

```
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/hello",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:1980": 1
    }
  }
}'
```

CSRF plugin have been disabled.
