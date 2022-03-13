---
title: proxy-control
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

`proxy-control` 能够动态地控制 Nginx 代理的行为。

**这个插件需要APISIX在 [APISIX-OpenResty](../how-to-build.md#步骤6：为-apache-apisix-构建-openresty)上运行。**

## 属性

| 名称      | 类型          | 必选项 | 默认值    | 有效值                                                                    | 描述                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| request_buffering | boolean        | 可选    |  true            |  | 动态设置 [`proxy_request_buffering`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_request_buffering) |

## 如何启用

以下是一个示例，在指定路由中启用插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/upload",
    "plugins": {
        "proxy-control": {
            "request_buffering": false
        }
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

使用 `curl` 去测试：

```shell
curl -i http://127.0.0.1:9080/upload -d @very_big_file
```

将不会在 error 日志中找到 "a client request body is buffered to a temporary file" 。

## 禁用插件

当您要禁用这个插件时，这很简单，您可以在插件配置中删除相应的 json 配置，无需重新启动服务，它将立即生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/upload",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

现在就已经移除 `proxy-control` 插件了。其他插件的开启和移除也是同样的方法。
