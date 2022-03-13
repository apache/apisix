---
title: gzip
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

`gzip` 插件能动态设置 `Nginx` 的压缩行为。

**该插件要求 `APISIX` 运行在 [APISIX-OpenResty](../how-to-build.md#步骤6：为-apache-apisix-构建-openresty) 上。**

## 属性

| 名称           | 类型                 | 必选项 | 默认值        | 有效值                                                                      | 描述                                                                                                                                         |
| --------------------------------------| ------------| -------------- | -------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| types          | array[string] or "*" | 可选    |  ["text/html"] |          | 动态设置 [`gzip_types`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_types) 指令，特殊值 `"*"` 匹配任何 MIME 类型 |
| min_length     | integer              | 可选    |  20            | >= 1     | 动态设置 [`gzip_min_length`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_min_length) 指令 |
| comp_level     | integer              | 可选    |  1             | [1, 9]   | 动态设置 [`gzip_comp_level`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_comp_level) 指令 |
| http_version   | number               | 可选    |  1.1           | 1.1, 1.0 | 动态设置 [`gzip_http_version`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_http_version) 指令 |
| buffers.number | integer              | 可选    |  32            | >= 1     | 动态设置 [`gzip_buffers`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_buffers) 指令 |
| buffers.size   | integer              | 可选    |  4096          | >= 1     | 动态设置 [`gzip_buffers`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_buffers) 指令 |
| vary | boolean                        | 可选    |  false         |          | 动态设置 [`gzip_vary`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_vary) 指令 |

## 如何启用

下面是一个示例，在指定的 `route` 上开启了 `gzip` 插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "gzip": {
            "buffers": {
                "number": 8
            }
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

使用 `curl` 访问：

```shell
curl http://127.0.0.1:9080/index.html -i -H "Accept-Encoding: gzip"
HTTP/1.1 404 Not Found
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 21 Jul 2021 03:52:55 GMT
Server: APISIX/2.7
Content-Encoding: gzip

Warning: Binary output can mess up your terminal. Use "--output -" to tell
Warning: curl to output it to your terminal anyway, or consider "--output
Warning: <FILE>" to save to a file.
```

## 禁用插件

想要禁用该插件时很简单，在路由 `plugins` 配置块中删除对应 `JSON` 配置，不需要重启服务，即可立即生效禁用该插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
