---
title: 发布 API
keywords:
  - API 网关
  - Apache APISIX
  - 发布路由
  - 创建服务
description: 本文介绍了如何通过 Apache APISIX 发布服务和路由。
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

本文将引导你了解 APISIX 的上游、路由以及服务的概念，并介绍如何通过 APISIX 发布你的 API。

## 概念介绍

### 上游

[Upstream](../terminology/upstream.md) 也称为上游，上游是对虚拟主机的抽象，即应用层服务或节点的抽象。

上游的作用是按照配置规则对服务节点进行负载均衡，它的地址信息可以直接配置到路由或服务上。当多个路由或服务引用同一个上游时，可以通过创建上游对象，在路由或服务中使用上游 ID 的方式引用上游，减轻维护压力。

### 路由

[Route](../terminology/route.md) 也称为路由，是 APISIX 中最基础和最核心的资源对象。

APISIX 可以通过路由定义规则来匹配客户端请求，根据匹配结果加载并执行相应的[插件](../terminology/plugin.md)，最后把请求转发给到指定的上游服务。路由中主要包含三部分内容：匹配规则、插件配置和上游信息。

### 服务

[Service](../terminology/service.md) 也称为服务，是某类 API 的抽象（也可以理解为一组 Route 的抽象）。它通常与上游服务抽象是一一对应的，Route 与 Service 之间，通常是 N:1 的关系。

## 前提条件

在进行如下操作前，请确保你已经通过 Docker [启动 APISIX](../installation-guide.md)。

## 公开你的服务

1. 创建上游。

创建一个包含 `httpbin.org` 的上游服务，你可以使用它进行测试。这是一个返回服务，它将返回我们在请求中传递的参数。

```shell
curl "http://127.0.0.1:9180/apisix/admin/upstreams/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

在该命令中，我们指定了 Apache APISIX 的 Admin API Key 为 `edd1c9f034335f136f87ad84b625c8f1`，并且使用 `roundrobin` 作为负载均衡机制，并设置了 `httpbin.org:80` 为上游服务。为了将该上游绑定到路由，此处需要把 `upstream_id` 设置为 `1`。此处你可以在 `nodes` 下指定多个上游，以达到负载均衡的效果。

如需了解更多信息，请参考[上游](../terminology/upstream.md)。

2. 创建路由。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream_id": "1"
}'
```

:::note 注意

创建上游非必须步骤，你可以通过在路由中，添加 `upstream` 对象，达到上述的效果。例如：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

:::

3. 测试路由。

在创建完成路由后，你可以通过以下命令测试路由是否正常：

```
curl -i -X GET "http://127.0.0.1:9080/anything/get?foo1=bar1&foo2=bar2" -H "Host: example.com"
```

该请求将被 APISIX 转发到 `http://httpbin.org:80/anything/get?foo1=bar1&foo2=bar2`。

## 更多教程

你可以查看[保护 API](./protect-api.md) 来保护你的 API。

接下来，你可以通过 APISIX 的一些[插件](../plugins/batch-requests.md)，实现更多功能。
