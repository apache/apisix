---
title: jwt-auth
keywords:
  - APISIX
  - Plugin
  - JWT Auth
  - jwt-auth
description: 本文介绍了关于 Apache APISIX `jwt-auth` 插件的基本信息及使用方法。
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

`jwt-auth` 插件用于将 [JWT](https://jwt.io/) 身份验证添加到 [Service](../terminology/service.md) 或 [Route](../terminology/route.md) 中。

通过 Consumer 将其密匙添加到查询字符串参数、请求头或 `cookie` 中用来验证其请求。

## 属性

Consumer 端：

| 名称          | 类型     | 必选项 | 默认值  | 有效值                      | 描述                                                                                                          |
| ------------- | ------- | ----- | ------- | --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| key           | string  | 是    |         |                             | Consumer 的 `access_key` 必须是唯一的。如果不同 Consumer 使用了相同的 `access_key` ，将会出现请求匹配异常。 |
| secret        | string  | 否    |         |                             | 加密秘钥。如果未指定，后台将会自动生成。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。   |
| public_key    | string  | 否    |         |                             | RSA 或 ECDSA 公钥， `algorithm` 属性选择 `RS256` 或 `ES256` 算法时必选。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。       |
| private_key   | string  | 否    |         |                             | RSA 或 ECDSA 私钥， `algorithm` 属性选择 `RS256` 或 `ES256` 算法时必选。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。       |
| algorithm     | string  | 否    | "HS256" | ["HS256", "HS512", "RS256", "ES256"] | 加密算法。                                                                                                      |
| exp           | integer | 否    | 86400   | [1,...]                     | token 的超时时间。                                                                                              |
| base64_secret | boolean | 否    | false   |                             | 当设置为 `true` 时，密钥为 base64 编码。                                                                                         |
| lifetime_grace_period | integer | 否    | 0  | [0,...]                  | 定义生成 JWT 的服务器和验证 JWT 的服务器之间的时钟偏移。该值应该是零（0）或一个正整数。 |

注意：schema 中还定义了 `encrypt_fields = {"secret", "private_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Route 端：

| 名称   | 类型    | 必选项 | 默认值         | 描述                                                    |
| ------ | ------ | ------ | ------------- |---------------------------------------------------------|
| header | string | 否     | authorization | 设置我们从哪个 header 获取 token。                         |
| query  | string | 否     | jwt           | 设置我们从哪个 query string 获取 token，优先级低于 header。  |
| cookie | string | 否     | jwt           | 设置我们从哪个 cookie 获取 token，优先级低于 query。        |
| hide_credentials | boolean | 否     | false  | 该参数设置为 `true` 时，则不会将含有认证信息的 header\query\cookie 传递给 Upstream。|

您可以使用 [HashiCorp Vault](https://www.vaultproject.io/) 实施 `jwt-auth`，以从其[加密的 KV 引擎](https://www.vaultproject.io/docs/secrets/kv) 使用 [APISIX Secret](../terminology/secret.md) 资源。

## 接口

该插件会增加 `/apisix/plugin/jwt/sign` 接口。

:::note

你需要通过 [public-api](../../../en/latest/plugins/public-api.md) 插件来暴露它。

:::

## 启用插件

如果想要启用插件，就必须使用 JWT token 创建一个 Consumer 对象，并将 Route 配置为使用 JWT 身份验证。

首先，你可以通过 Admin API 创建一个 Consumer：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

:::note

`jwt-auth` 默认使用 `HS256` 算法，如果使用 `RS256` 算法，需要指定算法，并配置公钥与私钥，示例如下：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

:::

创建 Consumer 对象后，你可以创建 Route 进行验证：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "jwt-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

首先，你需要为签发 token 的 API 配置一个 Route，该路由将使用 [public-api](../../../en/latest/plugins/public-api.md) 插件。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/jas \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/apisix/plugin/jwt/sign",
    "plugins": {
        "public-api": {}
    }
}'
```

之后就可以通过调用它来获取 token 了。

* 没有额外的 payload:

```shell
curl http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
```

```
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMXx.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI
```

* 有额外的 payload:

```shell
curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
```

```
HTTP/1.1 200 OK
Date: Wed, 21 Apr 2021 06:43:59 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.4

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1bmFtZSI6InRlc3QiLCJ1aWQiOjEwMDAwLCJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTYxOTA3MzgzOX0.jI9-Rpz1gc3u8Y6lZy8I43RXyCu0nSHANCvfn0YZUCY
```

现在你可以使用获取到的 token 进行请求尝试

* token 放到请求头中：

```shell
curl http://127.0.0.1:9080/index.html \-H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes
<!DOCTYPE html>
<html lang="cn">
...
```

* 缺少 token

```shell
curl http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

* token 放到请求参数中：

```shell
curl http://127.0.0.1:9080/index.html?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* token 放到 cookie 中：

```shell
curl http://127.0.0.1:9080/index.html --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

## 禁用插件

当你需要禁用 `jwt-auth` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
