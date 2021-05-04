---
title: proxy-mirror
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

启用该插件后，网关将支持对请求进行镜像复制，以便更好地进行旁路的请求分析。

## 参数

| 参数名 | 类型   | 必选 | 描述                                                                                         |
| ------ | ------ | ---- | -------------------------------------------------------------------------------------------- |
| host   | 字符串 | 否   | 镜像服务地址，格式：`协议://主机名:端口号`，例如 `http://127.0.0.1:9797`，无需包含其它信息。 |

## 使用 AdminAPI 启用插件

创建路由并绑定该插件：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "proxy-mirror": {
      "host": "http://127.0.0.1:9797"
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

测试本插件是否生效，需要在指定的镜像服务侧进行测试。例如：在 `http://127.0.0.1:9797` 启动一个服务，当访问 `http://127.0.0.1:9080/get` 时，可以在 `http://127.0.0.1:9797` 感知到请求。

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
