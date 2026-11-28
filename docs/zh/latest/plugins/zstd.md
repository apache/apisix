---
title: Zstandard 压缩（zstd）
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - zstd
description: 本文介绍了 Apache APISIX 的 zstd 插件。
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
-->

## 描述

`zstd` 插件在客户端发送 `Accept-Encoding: zstd` 时使用 [Zstandard](https://facebook.github.io/zstd/) 压缩 HTTP 响应（`Content-Encoding: zstd`）。它与 [brotli](../brotli.md) 插件的工作方式相同，面向支持 [RFC 9659](https://datatracker.ietf.org/doc/html/rfc9659) 定义的 zstd 内容编码的客户端，例如较新版本的 Chrome 和 Firefox。

## 前提条件

该插件依赖 `libzstd` 共享库，大多数系统已预装。如果缺少，可以通过如下命令安装：

``` shell
sudo apt-get install libzstd1
```

或者在 macOS 上：

``` shell
brew install zstd
```

:::caution

如果上游返回的是压缩后的响应，`zstd` 插件将不会再次压缩。

:::

## 属性

| 名称           | 类型                 | 必选项 | 默认值        | 有效值        | 描述                                                                             |
|----------------|----------------------|-------|---------------|--------------|-----------------------------------------------------------------------------------------|
| types          | array[string] 或 "*" | 否    | ["text/html"] |              | 设置需要压缩的 MIME 类型。特殊值 `"*"` 匹配任意 MIME 类型。 |
| min_length     | integer              | 否    | 20            | >= 1         | 设置触发压缩的最小响应长度，单位为字节。 |
| comp_level     | integer              | 否    | 3             | [1, 19]      | 设置 zstd 压缩等级。不允许高于 19，因为更高的等级会将解码窗口扩大到超过 [RFC 9659](https://datatracker.ietf.org/doc/html/rfc9659) 要求 HTTP 解码端必须支持的 8 MB。 |
| http_version   | number               | 否    | 1.1           | 1.1, 1.0     | 与 `gzip_http_version` 指令类似，设置触发压缩所需的最小 HTTP 协议版本。 |
| vary           | boolean              | 否    | false         |              | 与 `gzip_vary` 指令类似，控制是否插入 "Vary: Accept-Encoding" 响应头。 |

## 启用插件

以下示例展示了如何在指定路由上启用 `zstd` 插件：

:::note
您可以这样从 `config.yaml` 中获取 `admin_key`，并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "plugins": {
        "zstd": {
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

## 测试插件

配置完成后，当客户端声明支持时响应将被压缩：

```shell
curl -i -H "Accept-Encoding: zstd" http://127.0.0.1:9080/ --output compressed.zst
```

```
HTTP/1.1 200 OK
Content-Encoding: zstd
```

未发送 `Accept-Encoding: zstd` 的请求将收到未压缩的响应。

## 删除插件

当你需要删除 `zstd` 插件时，可以从路由配置中删除相应的 JSON 配置。APISIX 将自动重新加载配置，无需重启。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```
