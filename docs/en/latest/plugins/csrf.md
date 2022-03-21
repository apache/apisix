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

## Description

The `CSRF` plugin based on the [`Double Submit Cookie`](https://en.wikipedia.org/wiki/Cross-site_request_forgery#Double_Submit_Cookie) way, protect your API from CSRF attacks. This plugin considers the `GET`, `HEAD` and `OPTIONS` methods to be safe operations. Therefore calls to the `GET`, `HEAD` and `OPTIONS` methods are not checked for interception.

In the following we define `GET`, `HEAD` and `OPTIONS` as the `safe-methods` and those other than these as `unsafe-methods`.

## Attributes

| Name             | Type    | Requirement | Default | Valid | Description                                                  |
| ---------------- | ------- | ----------- | ------- | ----- | ------------------------------------------------------------ |
|   name   |  string |    optional    | `apisix-csrf-token`  |    | The name of the token in the generated cookie. |
| expires |  number | optional | `7200` | | Expiration time(s) of csrf cookie. |
| key | string | required |  |  | The secret key used to encrypt the cookie. |

**Note: When expires is set to 0 the plugin will ignore checking if the token is expired or not.**

## How To Enable

1. Create the route and enable the plugin.

```shell
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

2. Using `GET` requests `/hello`, a cookie with an encrypted token is received in the response. Token name is the `name` field set in the plugin configuration, if not set, the default value is `apisix-csrf-token`.

Please note: We return a new cookie for each request.

3. In subsequent unsafe-methods requests to this route, you need to read the encrypted token from the cookie and append the token to the `request header`, setting the field name to the `name` in the plugin configuration.

## Test Plugin

Direct access to the '/hello' route using a `POST` method will return an error:

```shell
curl -i http://127.0.0.1:9080/hello -X POST

HTTP/1.1 401 Unauthorized
...
{"error_msg":"no csrf token in headers"}
```

When accessed with a GET request, the correct return and a cookie with an encrypted token are obtained:

```shell
curl -i http://127.0.0.1:9080/hello

HTTP/1.1 200 OK
Set-Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==;path=/;Expires=Mon, 13-Dec-21 09:33:55 GMT
```

The token needs to be read from the cookie and carried in the request header in subsequent unsafe-methods requests.

For example, use [js-cookie](https://github.com/js-cookie/js-cookie) read cookie and [axios](https://github.com/axios/axios) send request in client:

```js
const token = Cookie.get('apisix-csrf-token');

const instance = axios.create({
  headers: {'apisix-csrf-token': token}
});
```

You also need to make sure that you carry the cookie.

Use curl send request:

```shell
curl -i http://127.0.0.1:9080/hello -X POST -H 'apisix-csrf-token: eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==' -b 'apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ=='

HTTP/1.1 200 OK
```

## Disable Plugin

Send a request to update the route to disable the plugin:

```shell
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

The CSRF plugin has been disabled.
