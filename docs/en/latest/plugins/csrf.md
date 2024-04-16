---
title: csrf
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Cross-site request forgery
  - csrf
description: The CSRF Plugin can be used to protect your API against CSRF attacks using the Double Submit Cookie method.
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

The `csrf` Plugin can be used to protect your API against [CSRF attacks](https://en.wikipedia.org/wiki/Cross-site_request_forgery) using the [Double Submit Cookie](https://en.wikipedia.org/wiki/Cross-site_request_forgery#Double_Submit_Cookie) method.

This Plugin considers the `GET`, `HEAD` and `OPTIONS` methods to be safe operations (`safe-methods`) and such requests are not checked for interception by an attacker. Other methods are termed as `unsafe-methods`.

## Attributes

| Name    | Type   | Required | Default             | Description                                                                                 |
|---------|--------|----------|---------------------|---------------------------------------------------------------------------------------------|
| name    | string | False    | `apisix-csrf-token` | Name of the token in the generated cookie.                                                  |
| expires | number | False    | `7200`              | Expiration time in seconds of the CSRF cookie. Set to `0` to skip checking expiration time. |
| key     | string | True     |                     | Secret key used to encrypt the cookie.                                                      |

NOTE: `encrypt_fields = {"key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Enable Plugin

The example below shows how you can enable the Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT-d '
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

The Route is now protected and trying to access it with methods other than `GET` will be blocked with a 401 status code.

Sending a `GET` request to the `/hello` endpoint will send back a cookie with an encrypted token. The name of the token can be set through the `name` attribute of the Plugin configuration and if unset, it defaults to `apisix-csrf-token`.

:::note

A new cookie is returned for each request.

:::

For subsequent requests with `unsafe-methods`, you need to read the encrypted token from the cookie and append the token to the request header by setting the field name to the `name` attribute in the Plugin configuration.

## Example usage

After you have configured the Plugin as shown above, trying to directly make a `POST` request to the `/hello` Route will result in an error:

```shell
curl -i http://127.0.0.1:9080/hello -X POST
```

```shell
HTTP/1.1 401 Unauthorized
...
{"error_msg":"no csrf token in headers"}
```

To get the cookie with the encrypted token, you can make a `GET` request:

```shell
curl -i http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 OK
Set-Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==;path=/;Expires=Mon, 13-Dec-21 09:33:55 GMT
```

This token must then be read from the cookie and added to the request header for subsequent `unsafe-methods` requests.

For example, you can use [js-cookie](https://github.com/js-cookie/js-cookie) to read the cookie and [axios](https://github.com/axios/axios) to send requests:

```js
const token = Cookie.get('apisix-csrf-token');

const instance = axios.create({
  headers: {'apisix-csrf-token': token}
});
```

Also make sure that you carry the cookie.

You can also use curl to send the request:

```shell
curl -i http://127.0.0.1:9080/hello -X POST -H 'apisix-csrf-token: eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==' -b 'apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ=='
```

```shell
HTTP/1.1 200 OK
```

## Delete Plugin

To remove the `csrf` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
