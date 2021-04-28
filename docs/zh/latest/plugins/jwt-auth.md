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

## 简介

启用该插件后，客户端访问路由、服务时需提供正确的 JSON Web Token，插件将从 HTTP 请求头、HTTP 查询参数（QueryString）或 Cookie 中获取凭证信息。

:::caution 注意
该插件需配合 Consumer 共同使用，为路由、服务增加该插件时，不需要进行配置。详情请见下方示例。
:::

## 参数

|    参数名     |  类型  | 必选  | 默认值 |          可选值          |                                   描述                                   |
| :-----------: | :----: | :---: | :----: | :----------------------: | :----------------------------------------------------------------------: |
|      key      | 字符串 |  是   |        |                          | 该值与 Consumer 相关联，会被存储到 Payload 中，请避免使用重复的 Key 值。 |
|    secret     | 字符串 |  否   |        |                          |      对 Payload 进行签名的密钥，若不设置，将会使用自动生成的密钥。       |
|  public_key   | 字符串 |  否   |        |                          |                  RSA 公钥。仅当使用 RS256 算法时必填。                   |
|  private_key  | 字符串 |  否   |        |                          |                  RSA 私钥。仅当使用 RS256 算法时必填。                   |
|   algorithm   | 字符串 |  否   | HS256  |    HS256,HS512,RS256     |                       对 Payload 进行签名的算法。                        |
|      exp      |  数字  |  否   | 86400  |         最小为 1         |                           Token 过期时间（秒）                           |
| base64_secret | 布尔值 |  否   | false  | 密钥是否被 base64 编码。 |

## 注意

使用本插件时，需访问 `/apisix/plugin/jwt/sign` 接口获取 Token，该接口应参照如下方式进行保护：[https://apisix.apache.org/docs/apisix/plugin-interceptors/](https://apisix.apache.org/docs/apisix/plugin-interceptors/)

## 使用 AdminAPI 启用插件

首先，创建消费者并配置 jwt-auth 插件：

```bash
# 场景1：使用默认的 HS256 算法进行加密
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/consumers -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "username": "consumer_username",
  "plugins": {
    "jwt-auth": {
      "key": "consumer-key",
      "secret": "jwt-secret"
    }
  }
}
'

# 场景2：使用指定的 RS256 算法进行加密，这需要指定公钥、私钥
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/consumers -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "username": "consumer_username",
  "plugins": {
    "jwt-auth": {
      "key": "consumer-key",
      "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----",
      "private_key": "-----BEGIN RSA PRIVATE KEY-----\n……\n-----END RSA PRIVATE KEY-----",
      "algorithm": "RS256"
    }
  }
}
'
```

其次，创建路由并绑定 jwt-auth 插件（该插件无需进行配置）：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "jwt-auth": {}
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```

接着，需要生成 Token：

```bash
# 场景1：生成不包含 Payload 的 Token

## Request
$ curl -i -X GET http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=consumer-key

## Response
HTTP/1.1 200 OK
Date: Wed, 28 Apr 2021 10:06:56 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE

# 场景2：生成包含 Payload 的 Token

## Request
$ curl -i -G --data-urlencode 'payload={"id":10000,"name":"test"}' http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=consumer-key

## Response
HTTP/1.1 200 OK
Date: Wed, 28 Apr 2021 10:18:37 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTE1MTcsImtleSI6ImNvbnN1bWVyLWtleSJ9.ZGD9MLRzdfYK-y1179gi8odB9FtoaunBlwrD1ysaFQk
```

最后，访问路由进行测试：

```bash
# 场景1：访问路由时，不携带 Token

## Request
$ curl -i -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 10:21:04 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Missing JWT token in request"}

# 场景2：访问路由时，将 Token 存放在 Authorization 中

## Request
$ curl -i -X GET http://127.0.0.1:9080/get -H "Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE"

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 457
Connection: keep-alive
Date: Wed, 28 Apr 2021 10:21:50 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6089373e-3c03e8be49b0bef2000a23a4",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 8.210.41.192",
  "url": "http://127.0.0.1/get"
}

# 场景3：访问路由时，将 Token 存放在 HTTP 查询参数中

## Request
$ curl -i -X GET http://127.0.0.1:9080/get?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 586
Connection: keep-alive
Date: Wed, 28 Apr 2021 10:22:22 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {
    "jwt": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6089375e-0e631aa5485ed6290d582bf4",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 8.210.41.192",
  "url": "http://127.0.0.1/get?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE"
}

# 场景4：访问路由时，将 Token 存放在 Cookie 中

## Request
$ curl -i -X GET http://127.0.0.1:9080/get --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 454
Connection: keep-alive
Date: Wed, 28 Apr 2021 10:22:57 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Cookie": "jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MTk2OTA4MTYsImtleSI6ImNvbnN1bWVyLWtleSJ9.ubUiKrLUMODdNww7nQi7GPwCLVt_PZQ4ovx0jZDEOvE",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-60893781-754dad6c4eaf22c25b89508e",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 8.210.41.192",
  "url": "http://127.0.0.1/get"
}
```

## 使用 AdminAPI 禁用插件

如果希望禁用插件，只需更新路由配置，从 plugins 字段移除该插件即可：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```
