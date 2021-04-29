---
title: limit-req
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

启用该插件后，网关将根据预设参数进行请求限速，该插件使用了漏桶算法。

## 参数

|    参数名     |  类型  | 必选  | 默认值 |                                  值范围                                   |                                    描述                                    |
| :-----------: | :----: | :---: | :----: | :-----------------------------------------------------------------------: | :------------------------------------------------------------------------: |
|     rate      | 整数型 |  是   |        |                                 rate > 0                                  | 允许的最大请求速率。大于 `rate` 但小于 `rate + burst` 的请求将被延迟处理。 |
|     burst     | 整数型 |  是   |        |                                burst >= 0                                 |                         允许被延迟处理的请求速率。                         |
|      key      | 字符串 |  是   |        | remote_addr,server_addr,http_x_real_ip,http_x_forwarded_for,consumer_name |                         用于限制请求速率的关键字。                         |
| rejected_code | 整数型 |  否   |  503   |                                 200 ~ 599                                 |             当请求速率超过 `rate + burst` 后，将返回该状态码。             |
## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下配置表示：请求速率限制为 1 次/秒；当请求速率介于 1~3 时，这些请求将被延迟处理；当请求速率大于 3 时，请求将会被拒绝，并返回 503 状态码。

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "limit-req": {
      "rate": 1,
      "burst": 2,
      "rejected_code": 503,
      "key": "remote_addr"
    }
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

接着，访问路由进行测试：

```bash
## Request
$ curl -i http://127.0.0.1:9080/get & curl -i http://127.0.0.1:9080/get & curl -i http://127.0.0.1:9080/get & curl -i http://127.0.0.1:9080/get

## Response
HTTP/1.1 200 OK

HTTP/1.1 200 OK
HTTP/1.1 200 OK

HTTP/1.1 503 Service Temporarily Unavailable
```

当同时发出 4 次请求时，第 1 个请求将返回 200 状态码，第 2、3 个请求延迟返回 200 状态码，第 4 个请求将返回 503 状态码。这表示该插件及其配置已生效。

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
