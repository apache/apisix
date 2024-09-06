---
title: gzip
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - gzip
description: 本文介绍了关于 Apache APISIX `gzip` 插件的基本信息及使用方法。
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

`gzip` 插件能动态设置 [NGINX](https://docs.nginx.com/nginx/admin-guide/web-server/compression/) 的压缩行为。
当启用 `gzip` 插件时，客户端在发起请求时需要在请求头中添加 `Accept-Encoding: gzip`，以表明客户端支持 `gzip` 压缩。APISIX 在接收到请求后，会根据客户端的支持情况和服务器配置动态判断是否对响应内容进行 gzip 压缩。如果判定条件得到满足，APISIX 将在响应头中添加 `Content-Encoding: gzip` 字段，以指示响应内容已经通过 `gzip` 压缩。在客户端接收到响应后，根据响应头中的 `Content-Encoding` 字段使用相应的解压缩算法对响应内容进行解压，从而获取原始的响应内容。

:::info IMPORTANT

该插件要求 Apache APISIX 运行在 [APISIX-Runtime](../FAQ.md#如何构建-apisix-runtime-环境) 上。

:::

## 属性

| 名称           | 类型                  | 必选项  | 默认值         | 有效值    | 描述                                                                                                                            |
| ---------------| -------------------- | ------- | -------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------- |
| types          | array[string] or "*" | 否      |  ["text/html"] |          | 动态设置 [`gzip_types`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_types) 指令，特殊值 `"*"` 匹配任何 MIME 类型。 |
| min_length     | integer              | 否      |  20            | >= 1     | 动态设置 [`gzip_min_length`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_min_length) 指令。                      |
| comp_level     | integer              | 否      |  1             | [1, 9]   | 动态设置 [`gzip_comp_level`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_comp_level) 指令。                      |
| http_version   | number               | 否      |  1.1           | 1.1, 1.0 | 动态设置 [`gzip_http_version`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_http_version) 指令。                  |
| buffers.number | integer              | 否      |  32            | >= 1     | 动态设置 [`gzip_buffers`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_buffers) 指令 参数 `number`。                            |
| buffers.size   | integer              | 否      |  4096          | >= 1     | 动态设置 [`gzip_buffers`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_buffers) 指令参数 `size`。单位为字节。                            |
| vary           | boolean              | 否      |  false         |          | 动态设置 [`gzip_vary`](https://nginx.org/en/docs/http/ngx_http_gzip_module.html#gzip_vary) 指令。                                  |

## 启用插件

以下示例展示了如何在指定路由中启用 `gzip` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl http://127.0.0.1:9080/index.html -i -H "Accept-Encoding: gzip"
```

```
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

## 删除插件

当你需要禁用 `gzip` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
