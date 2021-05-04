---
title: referer-restriction
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

启用该插件后，网关将根据预设的主机名白名单，通过判断请求头中 Referer 信息以判断是否限制该请求。

## 参数

| 参数名         | 类型       | 必选 | 默认值 | 描述                                                  |
| -------------- | ---------- | ---- | ------ | ----------------------------------------------------- |
| whitelist      | 字符串数组 | 是   |        | 主机名白名单，支持使用通配符域名，如 `*.hostname.com` |
| bypass_missing | 布尔值     | 否   | false  | 当 Referer 不存在或格式异常时，是否忽略检查。         |

## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下配置表示：当请求的 Referer 匹配 `xx.com` 或 `*.xx.com` 时，允许请求访问，否则拒绝。

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "referer-restriction": {
      "bypass_missing": true,
      "whitelist": [
          "xx.com",
          "*.xx.com"
      ]
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
# 场景1：请求携带白名单内的 Referer
## Request
$ curl -i http://127.0.0.1:9080/get -H "Referer: http://xx.com/x"

## Response
HTTP/1.1 200 OK

# 场景2：请求携带白名单外的 Referer
## Request
$ curl -i http://127.0.0.1:9080/get -H "Referer: http://yy.com/x"

## Response
HTTP/1.1 403 Forbidden
Date: Thu, 29 Apr 2021 06:32:33 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Your referer host is not allowed"}

# 场景3：请求不携带 Referer
## Request
$ curl -i http://127.0.0.1:9080/get

## Response
HTTP/1.1 200 OK
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
