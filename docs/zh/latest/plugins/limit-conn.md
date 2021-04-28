---
title: limit-conn
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

启用该插件后，网关将根据预设参数限制该路由并发请求数量。

## 参数

|      参数名称      |  类型  | 必选  | 默认值 |                                 使用范围                                  |                                      描述                                      |
| :----------------: | :----: | :---: | :----: | :-----------------------------------------------------------------------: | :----------------------------------------------------------------------------: |
|        conn        | 整数型 |  是   |        |                                 conn > 0                                  | 允许的最大并发请求数量。大于 conn 但小于 `conn + burst` 的请求，将被延迟处理。 |
|       burst        | 整数型 |  是   |        |                                burst >= 0                                 |                        允许被延迟处理的并发请求数量量。                        |
| default_conn_delay |  数值  |  是   |        |                          default_conn_delay > 0                           |                         默认的典型请求的处理延迟时间。                         |
|        key         | 字符串 |  是   |        | remote_addr,server_addr,http_x_real_ip,http_x_forwarded_for,consumer_name |                           用于限制并发级别的关键字。                           |
|   rejected_code    | 整数型 |  否   |  503   |             状态码介于 200～599                     conn > 0              |             当并发请求数量超过 `conn + burst` 后，将返回该状态码。             |

## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下配置表示：只允许同时有一个请求访问该路由，否则会返回 503 状态码。

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "limit-conn": {
      "conn": 1,
      "burst": 0,
      "default_conn_delay": 0.1,
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
$ curl -i http://127.0.0.1:9080/get & curl -i http://127.0.0.1:9080/get

## Response
HTTP/1.1 503 Service Temporarily Unavailable
Date: Wed, 28 Apr 2021 14:28:47 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 194
Connection: keep-alive
Server: APISIX/2.5

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
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
