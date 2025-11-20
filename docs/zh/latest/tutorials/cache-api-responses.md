---
title: API 响应缓存
keywords:
  - API 网关
  - Apache APISIX
  - 缓存
  - 性能
description: This tutorial will focus primarily on handling caching at the API Gateway level by using Apache APISIX API Gateway and you will learn how to use proxy-caching plugin to improve response efficiency for your Web or Microservices API.
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

本教程将主要介绍如何在 **API 网关** 级别进行缓存处理，使用 **Apache APISIX API 网关**，你将学习如何使用 **proxy-cache** 插件来提升 Web 或微服务 API 的响应效率。

**本次教程涵盖的内容概览：**

* API 网关中的缓存
* 关于 [Apache APISIX API 网关](https://apisix.apache.org/zh/docs/apisix/getting-started/)
* 运行演示项目 [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker)
* 配置 [Proxy Cache](https://apisix.apache.org/zh/docs/apisix/plugins/proxy-cache/) 插件
* 验证代理缓存功能

## 通过缓存提升性能

在构建 API 时，你希望保持其简单且高效。当并发请求需要访问相同数据量增加时，你可能会遇到一些问题，从而考虑引入 **缓存**：

* 某些 API 请求存在延迟，明显影响用户体验。
* 从数据库获取数据响应时间过长。
* API 的高吞吐量可能威胁到其可用性。
* 网络故障导致频繁访问的 API 信息获取失败。

## API 网关中的缓存

[缓存](https://zh.wikipedia.org/wiki/%E7%BC%93%E5%AD%98)能够存储并获取网络请求及其对应的响应。在 Web 应用中，缓存可以发生在不同层级：

* 边缘缓存或 CDN
* 数据库缓存
* 服务器缓存（API 缓存）
* 浏览器缓存

**反向代理缓存（Reverse Proxy Caching）** 是另一种缓存机制，通常在 **API 网关** 内部实现。它可以减少对后端接口的调用次数，并通过缓存上游响应来提高 API 请求的延迟表现。如果 API 网关缓存中存在请求资源的最新副本，它会直接使用该副本响应请求，而无需访问后端服务。如果未命中缓存，请求将转发到目标上游服务（后端服务）。

## Apache APISIX API 网关代理缓存

借助 **Apache APISIX**，你可以使用 [proxy-cache](https://apisix.apache.org/zh/docs/apisix/plugins/proxy-cache/) 插件为 API 启用缓存，从而缓存 API 端点的响应并提升性能。该插件可以与其他插件组合使用，目前支持基于磁盘的缓存。

要缓存的数据可以通过 **responseCodes**、**requestModes** 进行过滤，也可以使用 **noCache** 和 **cacheByPass** 属性进行更复杂的过滤。你还可以在插件配置中指定缓存的过期时间或内存容量。更多配置项请参考 `proxy-cache` 插件的 [属性说明](https://apisix.apache.org/zh/docs/apisix/plugins/proxy-cache/)。

有了这些基础，我们接下来将通过一个例子演示如何使用 **Apache APISIX** 的 `proxy-cache` 插件，并将其应用于 **ASP.NET Core Web API** 的单个端点。

## 运行演示项目

到目前为止，我假设你已经启动并运行了演示项目 [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker)。你可以在 **GitHub** 上查看完整源码，以及如何通过 **Docker CLI** 构建多容器 **APISIX** 的说明。

在 **ASP.NET Core 项目** 中，有一个简单的 API，用于从服务层获取所有产品列表，位于 [ProductsController.cs](https://github.com/Boburmirzo/apisix-dotnet-docker/blob/main/ProductApi/Controllers/ProductsController.cs) 文件中。

假设这个产品列表通常每天只更新一次，而该端点每天需要处理数十亿次请求来部分或全部获取产品列表。在这种场景下，使用 `proxy-cache` 插件进行 API 缓存将非常有用。为了演示的目的，我们仅为 `GET` 方法启用缓存。

> 理想情况下，`GET` 请求应该默认是可缓存的——除非出现特殊条件。

## 配置 Proxy Cache 插件

现在，让我们开始在项目的 **Apache APISIX 声明式配置文件 `config.yaml`** 中添加 `proxy-cache` 插件。由于在当前项目中，我们还没有注册本次演示要使用的插件，因此需要将 `proxy-cache` 插件名称添加到插件列表末尾：

```yaml
plugins:
 - http-logger
 - ip-restriction
 …
 - proxy-cache
```

如果你需要指定缓存相关参数（如 **disk_size**、**memory_size**），也可以在同一个文件中添加缓存配置，例如：

```yaml
proxy_cache:
 cache_ttl: 10s # 如果上游未指定缓存时间，则使用默认缓存时间
 zones:
 - name: disk_cache_one # 缓存名称。管理员可以在 Admin API 中按名称指定使用哪个缓存
 memory_size: 50m # 用于存储缓存索引的共享内存大小
 disk_size: 1G # 用于存储缓存数据的磁盘大小
 disk_path: "/tmp/disk_cache_one" # 缓存数据存储路径
 cache_levels: "1:2" # 缓存的层级结构
```

接下来，我们可以直接运行 `apisix reload` 命令来重新加载最新的插件代码，而无需重启 Apache APISIX。重新加载新插件的命令如下：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```

然后，我们运行两个 curl 命令来为 `/api/products` 端点配置 **Upstream** 和 **Route**。首先，创建一个示例 Upstream（也就是我们的 API 服务器）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "productapi:80": 1
  }
}'
```

接下来，我们为 `/api/products` 添加一个具备缓存能力的路由，通过在 `plugins` 属性中设置 `proxy-cache` 插件，并通过 **upstream_id** 引用上游服务，将请求转发到 API 服务器：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '{
  "name": "Route for API Caching",
  "methods": [
    "GET"
  ],
  "uri": "/api/products",
  "plugins": {
    "proxy-cache": {
      "cache_key": [
        "$uri",
        "-cache-id"
      ],
      "cache_bypass": [
        "$arg_bypass"
      ],
      "cache_method": [
        "GET"
      ],
      "cache_http_status": [
        200
      ],
      "hide_cache_headers": true,
      "no_cache": [
        "$arg_test"
      ]
    }
  },
  "upstream_id": 1
}'
```

如上配置所示，我们定义了一些插件属性，表示只缓存 **GET 方法的成功响应（HTTP 200）**。

## 验证 Proxy Cache 功能

最后，我们可以测试代理缓存是否按预期工作。

我们将向 `/api/products` 路径发送多次请求，每次都应收到 `HTTP 200 OK` 响应。然而，响应头中的 `Apisix-Cache-Status` 会显示 **MISS**，表示当请求第一次访问路由时，该响应尚未缓存。此时，如果再次发送请求，你会看到响应已被缓存，`Apisix-Cache-Status` 显示 **HIT**。

首先，发送初始请求：

```shell
curl http://localhost:9080/api/products -i
```

响应示例：

```shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: MISS
```

当你再次调用该服务时，由于上一次请求已缓存，路由会返回缓存的响应：

```shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: HIT
```

如果在缓存的 **TTL（生存时间）** 结束后再次访问端点，你将得到：

```shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: EXPIRED
```

太棒了！我们已经为 API 端点启用了缓存。

### 额外测试案例

你也可以在 **Product Controller** 代码中添加一些延迟，并测量有缓存和无缓存情况下的响应时间：

```c#
[HttpGet]
public IActionResult GetAll()
{
    Console.Write("The delay starts.\n");
    System.Threading.Thread.Sleep(5000);
    Console.Write("The delay ends.");
    return Ok(_productsService.GetAll());
}
```

使用 `curl` 命令测量响应时间：

```shell
curl -i 'http://localhost:9080/api/products' -s -o /dev/null -w "Response time: %{time_starttransfer} seconds\n"
```

## 后续步骤

如我们所学，在 **Apache APISIX** 的帮助下，为 **ASP.NET Core Web API** 配置 API 响应缓存既简单又快速。它可以显著减少对端点的调用次数，并改善 API 请求的延迟表现。Apache APISIX 还提供了众多内置插件，你可以在 [插件中心](https://apisix.apache.org/plugins) 查看并根据需要使用。

## 推荐阅读

* 你可以参考 [Expose API](./protect-api.md) 学习如何发布你的第一个 API。
* 你可以参考 [Protect API](./protect-api.md) 学习如何保护你的 API。
