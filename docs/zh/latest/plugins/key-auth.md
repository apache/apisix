---
title: key-auth
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

启用该插件后，客户端访问路由、服务时需提供正确的密钥，插件将从 HTTP 请求头中获取凭证信息。

:::caution 注意
该插件需配合 Consumer 共同使用，为路由、服务增加该插件时，不需要进行配置。详情请见下方示例。
:::

## 参数

| 参数名 | 类型   | 必选 | 默认值 | 描述                                                                                           |
| ------ | ------ | ---- | ------ | ---------------------------------------------------------------------------------------------- |
| key    | 字符串 | 是   |        | 消费者访问资源进行身份验证时，需使用的密钥。请注意，不同消费者配置该插件时，需使用不同的密钥。 |

## 使用 AdminAPI 启用插件

首先，创建消费者并配置 key-auth 插件（密钥为：auth-key）：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/consumers -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "username": "consumer_username",
  "plugins": {
    "key-auth": {
      "key": "auth-key"
    }
  }
}
'
```

其次，创建路由并绑定 key-auth 插件（该插件无需进行配置）：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "key-auth": {}
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

最后，访问路由进行测试：

```bash
# 场景1：访问路由时，不携带密钥

## Request
$ curl -i -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 09:02:40 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Missing API key found in request"}

# 场景2：访问路由时，携带错误密钥

## Request
$ curl -i -X GET http://127.0.0.1:9080/get -H "apikey: wrong-key"

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 09:03:40 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Invalid API key in request"}

# 场景3：访问路由时，携带正确密钥（在 HTTP 请求头中）

## Request
$ curl -i -X GET http://127.0.0.1:9080/get -H "apikey: auth-key"

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 325
Connection: keep-alive
Date: Wed, 28 Apr 2021 09:03:53 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "auth-key",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-608924f9-4a20a14821ce0ae97337e9f8",
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
