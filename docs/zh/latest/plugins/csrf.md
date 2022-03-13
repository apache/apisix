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

## 描述

`CSRF` 插件基于 [`Double Submit Cookie`](https://en.wikipedia.org/wiki/Cross-site_request_forgery#Double_Submit_Cookie) 的方式，保护您的 API 免于 CSRF 攻击。本插件认为 `GET`、`HEAD` 和 `OPTIONS` 方法是安全操作。因此 `GET`、`HEAD` 和 `OPTIONS` 方法的调用不会被检查拦截。

在这里我们定义 `GET`, `HEAD` 和 `OPTIONS` 为 `safe-methods`，其他的请求方法为 `unsafe-methods`。

## 属性

| Name             | Type    | Requirement | Default | Valid | Description                                                  |
| ---------------- | ------- | ----------- | ------- | ----- | ------------------------------------------------------------ |
|   name   |  string |    optional    | `apisix-csrf-token`  |    | 生成的 Cookie 中的 token 的名字，需要使用这个名字在请求头携带 Cookie 中的内容 |
| expires |  number | optional | `7200` | | CSRF Cookie 的过期时间(秒) |
| key | string | required |  |  | 加密 token 的秘钥 |

**注意：当 expires 设置为 0 时插件将忽略检查 Token 是否过期**

## 如何启用

1. 创建一条路由并启用该插件。

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

这条路由已经开启保护，当你使用 GET 之外的方法访问，请求会被拦截并返回 401 状态码。

2. 使用 `GET` 请求 `/hello`，在响应中会有一个携带了加密 `token` 的 `Cookie`。Token 字段的名字为插件配置中的 `name` 值，如果没有配置该值，那么默认值为 `apisix-csrf-token`。

注意：每一个请求都会返回一个新的 Cookie。

3. 在后续的对该路由的 `unsafe-methods` 请求中，需要从 Cookie 中读取加密的 token，保证携带 Cookie 并在请求头部中携带该 token，请求头字段的名称为插件配置中的 `name`。

## 测试插件

直接对该路由发起 `POST` 请求会返回错误：

```shell
curl -i http://127.0.0.1:9080/hello -X POST

HTTP/1.1 401 Unauthorized
...
{"error_msg":"no csrf token in headers"}
```

当使用 GET 请求，返回中会有携带 token 的 Cookie：

```shell
curl -i http://127.0.0.1:9080/hello

HTTP/1.1 200 OK
Set-Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==;path=/;Expires=Mon, 13-Dec-21 09:33:55 GMT
```

在请求之前，需要从 Cookie 中读取 token，并在随后的 `unsafe-methods` 请求中的请求头中携带。

例如，在客户端使用 [js-cookie](https://github.com/js-cookie/js-cookie) 读取 Cookie，使用 [axios](https://github.com/axios/axios) 发送请求。

```js
const token = Cookie.get('apisix-csrf-token');

const instance = axios.create({
  headers: {'apisix-csrf-token': token}
});
```

你还需要确保你的请求携带了Cookie。

使用 curl 发送请求：

```shell
curl -i http://127.0.0.1:9080/hello -X POST -H 'apisix-csrf-token: eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==' -b 'apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ=='

HTTP/1.1 200 OK
```

## 禁用插件

发送一个更新路由的请求，以停用该插件：

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

CSRF 插件已经被停用。
