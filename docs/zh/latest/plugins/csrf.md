---
title: csrf
keywords:
  - Apache APISIX
  - API 网关
  - 跨站请求伪造攻击
  - Cross-site request forgery
  - csrf
description: CSRF 插件基于 Double Submit Cookie 的方式，帮助用户阻止跨站请求伪造攻击。

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

`csrf` 插件基于 [`Double Submit Cookie`](https://en.wikipedia.org/wiki/Cross-site_request_forgery#Double_Submit_Cookie) 的方式，保护用户的 API 免于 CSRF 攻击。

在此插件运行时，`GET`、`HEAD` 和 `OPTIONS` 会被定义为 `safe-methods`，其他的请求方法则定义为 `unsafe-methods`。因此 `GET`、`HEAD` 和 `OPTIONS` 方法的调用不会被检查拦截。

## 属性

| 名称             | 类型    | 必选项 | 默认值 | 有效值 | 描述         |
| ---------------- | ------- | ----------- | ------- | ----- |---------------------|
| name   | string | 否    | `apisix-csrf-token`  |    | 生成的 Cookie 中的 Token 名称，需要使用此名称在请求头携带 Cookie 中的内容。 |
| expires | number | 否 | `7200` | | CSRF Cookie 的过期时间，单位为秒。当设置为 `0` 时，会忽略 CSRF Cookie 过期时间检查。|
| key | string | 是 |  |  | 加密 Token 的密钥。        |

注意：schema 中还定义了 `encrypt_fields = {"key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

## 启用插件

以下示例展示了如何在指定路由上启用并配置 `csrf` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

当你使用 `GET` 之外的方法访问被保护的路由时，请求会被拦截并返回 `401` HTTP 状态码。

使用 `GET` 请求 `/hello` 时，在响应中会有一个携带了加密 Token 的 Cookie。Token 字段名称为插件配置中的 `name` 值，默认为 `apisix-csrf-token`。

:::note

每一个请求都会返回一个新的 Cookie。

:::

在后续对该路由进行的 `unsafe-methods` 请求中，需要从 Cookie 中读取加密的 Token，并在请求头中携带该 Token。请求头字段的名称为插件属性中的 `name`。

## 测试插件

启用插件后，使用 `curl` 命令尝试直接对该路由发起 `POST` 请求，会返回 `Unauthorized` 字样的报错提示：

```shell
curl -i http://127.0.0.1:9080/hello -X POST
```

```shell
HTTP/1.1 401 Unauthorized
...
{"error_msg":"no csrf token in headers"}
```

当发起 `GET` 请求时，返回结果中会有携带 Token 的 Cookie：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
Set-Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==;path=/;Expires=Mon, 13-Dec-21 09:33:55 GMT
```

在请求之前，用户需要从 Cookie 中读取 Token，并在后续的 `unsafe-methods` 请求的请求头中携带。

例如，你可以在客户端使用 [js-cookie](https://github.com/js-cookie/js-cookie) 读取 Cookie，使用 [axios](https://github.com/axios/axios) 发送请求：

```js
const token = Cookie.get('apisix-csrf-token');

const instance = axios.create({
  headers: {'apisix-csrf-token': token}
});
```

使用 `curl` 命令发送请求，确保请求中携带了 Cookie 信息，如果返回 `200` HTTP 状态码则表示请求成功：

```shell
curl -i http://127.0.0.1:9080/hello -X POST -H 'apisix-csrf-token: eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ==' -b 'apisix-csrf-token=eyJyYW5kb20iOjAuNjg4OTcyMzA4ODM1NDMsImV4cGlyZXMiOjcyMDAsInNpZ24iOiJcL09uZEF4WUZDZGYwSnBiNDlKREtnbzVoYkJjbzhkS0JRZXVDQm44MG9ldz0ifQ=='
```

```shell
HTTP/1.1 200 OK
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
