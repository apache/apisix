---
title: proxy-buffering
keywords:
  - APISIX
  - API 网关
  - Proxy Buffering
description: 本文介绍了 Apache APISIX proxy-buffering 插件的相关操作，你可以使用此插件按路由禁用 nginx 代理缓冲，这对于流式响应（如 Server-Sent Events）至关重要。
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

`proxy-buffering` 插件用于按路由控制 nginx 代理缓冲行为。禁用代理缓冲后，nginx 会将上游响应直接流式传输给客户端，而不会在内存或磁盘中积累完整响应体。该功能对以下场景至关重要：

- **Server-Sent Events（SSE）**：客户端需要实时接收事件，缓冲会延迟或中断数据流。
- **流式 API**：响应体较大或无限长，需要持续流式传输而无需等待完整响应。
- **实时数据推送**：任何需要低延迟传输部分响应的场景。

该插件工作在 `rewrite` 阶段，优先级为 **21991**，早于鉴权插件执行，可以影响 APISIX 流水线中代理 location 的选择。

## 属性

| 名称                    | 类型    | 必选项 | 默认值 | 描述                                                                                                                                              |
| ----------------------- | ------- | ------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| disable_proxy_buffering | boolean | 否     | false  | 设置为 `true` 时，将为该路由禁用 [`proxy_buffering`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering)，从而支持流式响应。 |

## 启用插件

以下示例展示了如何在指定路由上启用 `proxy-buffering` 插件以支持流式响应：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/sse",
    "plugins": {
        "proxy-buffering": {
            "disable_proxy_buffering": true
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

启用插件后，向该路由发送请求：

```shell
curl -i http://127.0.0.1:9080/sse
```

由于 `disable_proxy_buffering` 设置为 `true`，nginx 会将响应直接流式传输给客户端，对调用方透明，但消除了 nginx 引入的缓冲延迟。

要验证配置是否已正确保存：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key"
```

响应中将包含路由对象中的 `proxy-buffering` 插件配置。

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/sse",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
