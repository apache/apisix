---
title: basic-auth
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

启用该插件后，客户端访问路由、服务时需提供正确的用户名与密码，插件将从 HTTP 请求头 Authorization 中获取凭证信息。

:::caution 注意
该插件需配合 Consumer 共同使用，为路由、服务增加该插件时，不需要进行配置。详情请见下方示例。
:::

## 参数

| 参数名   | 类型   | 必选 | 默认值 | 描述                                                                                                                   |
| -------- | ------ | ---- | ------ | ---------------------------------------------------------------------------------------------------------------------- |
| username | 字符串 | 是   |        | 消费者访问资源进行身份验证时，需使用的用户名。请注意，不同消费者配置该插件时，需使用不同的用户名，否则将产生匹配异常。 |
| password | 字符串 | 是   |        | 消费者访问资源进行身份验证时，需使用的密码。                                                                           |

## 使用 AdminAPI 启用插件

首先，创建消费者并配置 basic-auth 插件（用户名为 foo，密码为 bar）：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/consumers -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "username": "consumer_username",
  "plugins": {
    "basic-auth": {
      "username": "foo",
      "password": "bar"
    }
  }
}
'
```

其次，创建路由并绑定 basic-auth 插件（注意：该插件无需进行配置）：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "basic-auth": {}
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
# 场景1：访问路由时，不传递用户名与密码：

## Request
$ curl -i -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 08:07:36 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
WWW-Authenticate: Basic realm='.'
Server: APISIX/2.5

{"message":"Missing authorization in request"}

# 场景2：访问路由时，使用不存在的用户名

## Request
$ curl -i --user bar:bar -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 08:11:23 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Invalid user key in authorization"}

# 场景3：访问路由时，使用错误的密码

## Request
$ curl -i --user foo:foo -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 08:12:05 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Password is error"}

# 场景4：访问路由时，使用正确的用户名与密码

## Request
$ curl -i --user foo:bar -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 342
Connection: keep-alive
Date: Wed, 28 Apr 2021 08:13:32 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic Zm9vOmJhcg==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6089192c-1050819b2b42a25375748181",
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
