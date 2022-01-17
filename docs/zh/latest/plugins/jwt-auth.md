---
title: jwt-auth
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

## 目录

- [**目录**](#目录)
- [**名字**](#名字)
- [**属性**](#属性)
- [**接口**](#接口)
- [**如何启用**](#如何启用)
  - [**启用具有 Vault 兼容性的 jwt-auth**](#启用具有-Vault-兼容性的-jwt-auth)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`jwt-auth` 是一个认证插件，它需要与 `consumer` 一起配合才能工作。

添加 JWT Authentication 到一个 `service` 或 `route`。 然后 `consumer` 将其密钥添加到查询字符串参数、请求头或 `cookie` 中以验证其请求。

有关 JWT 的更多信息，可参考 [JWT](https://jwt.io/) 查看更多信息。

`jwt-auth` 插件可以与 HashiCorp Vault 集成，用于存储和获取密钥，从其加密的 kv 引擎获取 RSA 密钥对。 阅读下面的 [例子](#enable-jwt-auth-with-vault-compatibility) 来了解它如何工作。

## 属性

| 名称          | 类型    | 必选项 | 默认值  | 有效值                      | 描述                                                                                                          |
| :------------ | :------ | :----- | :------ | :-------------------------- | :------------------------------------------------------------------------------------------------------------ |
| key           | string  | 必须   |         |                             | 不同的 `consumer` 对象应有不同的值，它应当是唯一的。不同 consumer 使用了相同的 `key` ，将会出现请求匹配异常。 |
| secret        | string  | 可选   |         |                             | 加密秘钥。如果您未指定，后台将会自动帮您生成。                                                                |
| public_key    | string  | 可选   |         |                             | RSA 公钥， `algorithm` 属性选择 `RS256` 算法时必填                                                            |
| private_key   | string  | 可选   |         |                             | RSA 私钥， `algorithm` 属性选择 `RS256` 算法时必填                                                            |
| algorithm     | string  | 可选   | "HS256" | ["HS256", "HS512", "RS256"] | 加密算法                                                                                                      |
| exp           | integer | 可选   | 86400   | [1,...]                     | token 的超时时间                                                                                              |
| base64_secret | boolean | 可选   | false   |                             | 密钥是否为 base64 编码                                                                                        |
| vault | object | 可选    |    |                             | Vault 是否用于密钥（HS256/HS512 的密钥或 RS256 的公钥和私钥）的存储和检索。该插件默认使用的 Vault 路径为 `kv/apisix/consumer/<consumer name>/jwt-auth` 用于检索密钥 |

**注意**: 要启用 Vault 集成，首先访问 [config.yaml](https://github.com/apache/apisix/blob/master/conf/config.yaml)，更新您的 Vault 服务器配置、主机地址和访问令牌。您可以在 vault 属性下的 [config-default.yaml](https://github.com/apache/apisix/blob/master/conf/config-default.yaml) 中查看 APISIX 的期望配置。

## 接口

插件会增加 `/apisix/plugin/jwt/sign` 这个接口，你可能需要通过 [interceptors](../plugin-interceptors.md)
来保护它。

## 如何启用

1. 创建一个 consumer 对象，并设置插件 `jwt-auth` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

`jwt-auth` 默认使用 `HS256` 算法，如果使用 `RS256` 算法，需要指定算法，并配置公钥与私钥，示例如下：

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

2. 创建 Route 或 Service 对象，并开启 `jwt-auth` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### 启用具有 Vault 兼容性的 jwt-auth

有时候在生产中拥有一个集中式密钥管理解决方案，如 `Vault` 是很自然的。您不必每次在您的组织更改部分签署密钥（HS256/HS512 的密钥或 RS256 的 public_key 和 private_key）时更新 APISIX 消费者。或者出于隐私考虑，您不想通过 APISIX admin APIs 使用密钥。APISIX 在这里为您提供了保障，`jwt-auth` 能够引用 Vault 的密钥。

**注意**：对于该集成支持的早期版本，该插件期望存储在 Vault 路径中的密钥名称为「`secret`，`public_key`，`private_key`」其中之一，方可成功使用该密钥。在未来的版本中，我们将添加对引用自定义命名键的支持。

要启用 Vault 的兼容性，只需要在 `jwt-auth` 插件内添加空的 Vault 对象。

1. 用在 Vault 储存的 HS256 签名密钥来进行 jwt 签名和认证。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "key-1",
            "vault": {}
        }
    }
}'
```

这里插件在 Vault 路径（`<vault.prefix from conf.yaml>/consumer/jack/jwt-auth`）中为消费者配置的用户名 `jack` 查找密钥 `secret`，并将其用于后续签名和 `jwt` 验证。如果在同一路径中没有找到密钥，该插件就会记录错误，无法执行 `jwt` 验证。

2. RS256 rsa 密钥对, 包括公钥和私钥都存粗在 Vault 中。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "kowalski",
    "plugins": {
        "jwt-auth": {
            "key": "rsa-keypair",
            "algorithm": "RS256",
            "vault": {}
        }
    }
}'
```

该插件在 Vault kv 路径（`<vault.prefix from conf.yaml>/consumer/kowalski/jwt-auth`）中为插件 Vault 配置中提到的用户名 `kowalski` 查询 `public_key` 和 `private_key` 密钥。如果没有找到，认证失败。

3. 公钥在消费者配置中，而私钥在 Vault 中。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "rico",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "algorithm": "RS256",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----"
            "vault": {}
        }
    }
}'
```

这个插件使用消费者配置中的 rsa 公钥，并直接使用从 Vault 中获取的私钥。

你可以使用 [APISIX Dashboard](https://github.com/apache/apisix-dashboard)，通过 web 界面来完成上面的操作。

1. 先增加一个 consumer：

![create a consumer](../../../assets/images/plugin/jwt-auth-1.png)

然后在 consumer 页面中添加 jwt-auth 插件：
![enable jwt plugin](../../../assets/images/plugin/jwt-auth-2.png)

2. 创建 Route 或 Service 对象，并开启 jwt-auth 插件：

![enabe jwt from route or service](../../../assets/images/plugin/jwt-auth-3.png)

## 测试插件

#### 首先进行登录获取 `jwt-auth` token:

* 没有额外的 payload:

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

* 有额外的 payload:

```shell
$ curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
HTTP/1.1 200 OK
Date: Wed, 21 Apr 2021 06:43:59 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.4

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1bmFtZSI6InRlc3QiLCJ1aWQiOjEwMDAwLCJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTYxOTA3MzgzOX0.jI9-Rpz1gc3u8Y6lZy8I43RXyCu0nSHANCvfn0YZUCY
```

#### 使用获取到的 token 进行请求尝试

* 缺少 token

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

* token 放到请求头中：

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

* token 放到请求参数中：

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

* token 放到 cookie 中：

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

## 禁用插件

当你想去掉 `jwt-auth` 插件的时候，很简单，在插件的配置中把对应的 `json` 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
