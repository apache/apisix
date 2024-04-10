---
title: jwe-decrypt
keywords:
  - Apache APISIX
  - API 网关
  - APISIX 插件
  - JWE Decrypt
  - jwe-decrypt
description: 本文档包含了关于 APISIX jwe-decrypt 插件的相关信息。
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

`jwe-decrypt` 插件，用于解密 APISIX [Service](../terminology/service.md) 或者 [Route](../terminology/route.md) 请求中的 [JWE](https://datatracker.ietf.org/doc/html/rfc7516) 授权请求头。

插件增加了一个 `/apisix/plugin/jwe/encrypt` 的内部 API，提供给 JWE 加密使用。解密时，秘钥应该配置在 [Consumer](../terminology/consumer.md)内。

## 属性

Consumer 配置：

| 名称          | 类型      | 必选项   | 默认值   | 有效值 | 描述                                                          |
|---------------|---------|-------|-------|-----|-------------------------------------------------------------|
| key           | string  | True  |       |     | Consumer 的唯一 key                                            |
| secret        | string  | True  |       |     | 解密密钥，必须为 32 位。秘钥可以使用 [Secret](../terminology/secret.md) 资源保存在密钥管理服务中 |
| is_base64_encoded | boolean | False | false |     | 如果密钥是 Base64 编码，则需要配置为 `true`                               |

:::note

注意，在启用 `is_base64_encoded` 后，你的 `secret` 长度可能会超过 32 位，你只需要保证在 Decode 后的长度仍然是 32 位即可。

:::

Route 配置：

| 名称             | 类型      | 必选项   | 默认值           | 描述                                                                         |
|----------------|---------|-------|---------------|----------------------------------------------------------------------------|
| header         | string  | True | Authorization | 指定请求头，用于获取加密令牌                                                             |
| forward_header | string  | True | Authorization | 传递给 Upstream 的请求头名称                                                        |
| strict         | boolean | False | true          | 如果为配置为 true，请求中缺失 JWE token 则抛出 `403` 异常。如果为 `false`, 在缺失 JWE token 的情况下不会抛出异常 |

## 启用插件

首先，基于 `jwe-decrypt` 插件创建一个 Consumer，并且配置解密密钥：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

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

下一步，基于 `jwe-decrypt` 插件创建一个路由，用于解密 authorization 请求头：

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

### 使用 JWE 加密数据

该插件创建了一个内部的 API `/apisix/plugin/jwe/encrypt` 以使用 JWE 进行加密。要公开它，需要创建一个对应的路由，并启用 [public-api](public-api.md) 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/jwenew -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/apisix/plugin/jwe/encrypt",
    "plugins": {
        "public-api": {}
    }
}'
```

向 API 发送一个请求，将 Consumer 中配置的密钥，以参数的方式传递给 URI，用于加密 payload 中的一些数据。

```shell
curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' 'http://127.0.0.1:9080/apisix/plugin/jwe/encrypt?key=user-key' -i
```

您应该看到类似于如下内容的响应结果，其中 JWE 加密的数据位于响应体中：

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

### 使用 JWE 解密数据

将加密数据放在 `Authorization` 请求头中，向 API 发起请求：

```shell
curl http://127.0.0.1:9080/anything/hello -H 'Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.hfzMJ0YfmbMcJ0ojgv4PYAHxPjlgMivmv35MiA.7nilnBt2dxLR_O6kf-HQUA' -i
```

您应该可以看到类似于如下的响应内容，其中 `Authorization` 响应头显示了有效的解密内容：

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

## 删除插件

要删除 `jwe-decrypt` 插件，您可以从插件配置中删除插件对应的 JSON 配置，APISIX 会自动加载，您不需要重新启动即可生效。

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
