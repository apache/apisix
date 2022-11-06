---
title: 缓存 API 响应
keywords:
  - API 网关
  - Apache APISIX
  - 缓存
  - 性能
description: 本文主要关注如何使用 APISIX 处理网关级别的缓存。通过本教程，用户能够了解如何使用`proxy-cache`插件为您的 Web 应用或微服务 API 提升响应效率。
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

本文主要关注如何使用 APISIX 处理网关级别的缓存。通过本教程，用户能够了解如何使用`proxy-cache`插件为您的 Web 应用或微服务 API 提升响应效率。

**本文概览:**

-  API 网关中如何进行缓存
-  [APISIX](https://apisix.apache.org/docs/apisix/getting-started/) 如何支持 API 网关缓存
- 运行示例项目 [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker)
- 配置 [Proxy Cache](https://apisix.apache.org/docs/apisix/plugins/proxy-cache/) 插件
- 验证缓存效果

## 通过缓存提升性能

我们总是希望构建简单快速的 API ，但随着 API 请求的并发数增加，如下问题日益凸显，此时考虑使用缓存：

- 请求延时增加，影响用户体验。
- 高并发传递到数据库，使得数据库查询时间明显增加。
- API可用性降低，甚至会时不时发生网络故障。

##  API 网关缓存

[缓存](https://en.wikipedia.org/wiki/Cache_(computing))能够将请求的响应存储下来，在下次请求到来时直接使用。在 Web 应用架构的不同层级中，缓存均有应用，比如：

- 浏览器缓存
- 边缘缓存或 CDN
- 服务端缓存（ API 缓存）
- 数据库缓存

本文讨论另一种缓存机制——**反向代理缓存**，通常在 API 网关中实现，通过在网关中缓存后端服务的响应，以达到减少对后端服务的访问次数，降低请求延迟的目的。

其基本工作原理为：如果API网关已经缓存了请求资源的最新副本，则直接用该副本响应请求，不会再请求后端服务；否则，请求将会被转发到对应的后端服务。

##  APISIX 网关缓存

在 APISIX 中，用户可通过 `proxy-cache` 插件开启缓存功能。当前支持基于磁盘和内存的缓存。

缓存的数据能够通过响应码（如 `200` 、 `201` ）、请求方法（如 `GET` 、 `HEAD` ）等进行过滤，也能通过 `no_cache` 、 `cache_bypass` 等属性配置更复杂的过滤。此外，还可指定缓存过期时间、内存容量等。具体参见[插件属性](https:// APISIX .apache.org/docs/ APISIX /plugins/proxy-cache/)。

了解了基本工作原理，下面我们来看一个由 APISIX 团队提供的使用 `proxy-cache` 插件的示例，该示例展现了一个具有单个端点的 ASP.NET 项目。

## 运行示例项目

首先将该示例项目（ [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker) ）运行起来。用户可在Github上获取完整源码，并了解如何用Docker命令行工具构建镜它。

此项目暴露了一个简单 API ——在 [ProductsControllers.cs](https://github.com/Boburmirzo/apisix-dotnet-docker/blob/main/ProductApi/Controllers/ProductsController.cs) 中调用sevice层获取产品列表。

假设该产品列表每天仅更新一次，而后端服务每天会接收数以亿计获取该列表的请求。此时， `proxy-cache` 插件就有了用武之地。作为演示，我们仅为 `GET` 请求开启缓存。

> 注意：一般来说，除特殊情况外，`GET`请求应默认开启缓存。

## 配置缓存插件

由于在当前项目中，我们尚未在 APISIX 中注册`proxy-cache`插件，所以首先需要注册，方法是将其添加在配置文件 `config.yaml` 的插件列表末尾：

``` yaml
plugins:
 - http-logger
 - ip-restriction
 ...
 - proxy-cache
```

用户也可以在该配置文件中添加缓存的配置信息，如 `disk_size`、`memory_size`等，如下：

``` yaml
proxy_cache:
 cache_ttl: 10s # default caching time if the upstream doesn't specify the caching time
 zones:
 - name: disk_cache_one # name of the cache. Admin can specify which cache to use in the Admin API by name
 memory_size: 50m # size of shared memory, used to store the cache index
 disk_size: 1G # size of disk, used to store the cache data
 disk_path: "/tmp/disk_cache_one" # path to store the cache data
 cache_levels: "1:2" # hierarchy levels of the cache
```

然后，我们可以直接运行 `reload` 命令在不重启 APISIX 的情况下加载最新配置，具体如下：

``` shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

接着，运行如下命令创建一个指向 `/api/products` 所在服务的 `upstream` 资源。

``` shell
curl "http://127.0.0.1:9180/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "productapi:80": 1
  }
}'
```

最后，添加新的 `route` ，配置 `proxy-cache` 插件开启缓存能力，并通过 `upstream_id` 引用上一步创建的上游服务。

``` shell
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

如上，配置完成，我们的配置中，仅会缓存 `GET` 请求成功后的响应。

## Validate Proxy Caching

为了验证缓存是否正常工作，我们可以向 `/api/products` 发送多个请求，每次都应该能得到 `HTTP 200 OK` 的响应。首次访问时，由于响应尚未被缓存，响应头 `Apisix-Cache-Status` 的值将会 `MISS` 。再次访问时，将会得到一个已缓存的响应， `Apisix-Cache-Status` 的值将会是 `HIT` 。

现在我们发送第一个请求：

``` shell
curl http://localhost:9080/api/products -i
```

响应如下：

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: MISS
```

再次访问时，由于前一个请求的响应已被缓存，所以这次访问将命中缓存，响应如下：

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: HIT
```

如果我们在缓存存活时间（ `time-to-live` ，简称 `TTL` ）之后访问，将会得到如下响应：

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: EXPIRED
```

至此，我们成功地为 API 开启了缓存。

### 进一步测试

我们也可以在 Product Controller 代码中手动添加延迟，用以对比有缓存和没有缓存时的响应时间：

``` c#
 [HttpGet]
 public IActionResult GetAll()
 {
 Console.Write("The delay starts.\n");
 System.Threading.Thread.Sleep(5000);
 Console.Write("The delay ends.");
 return Ok(_productsService.GetAll());
 }
```

测量响应耗时的 `curl` 命令如下：

```shell
curl -i 'http://localhost:9080/api/products' -s -o /dev/null -w "Response time: %{time_starttransfer} seconds\n"
```

## What's next

通过本文，我们了解到，有了 APISIX 的赋能，为示例项目设置 API 响应缓存将会非常简单。它能显著减少对后端服务的访问次数，降低 API 访问延迟。此外， APISIX 中还有很多其它内建的插件可用，具体请参考[插件中心](https://apisix.apache.org/plugins/)，根据需要取用。

## Recommended content

你可参考 [发布 API ](https://apisix.apache.org/zh/docs/apisix/tutorials/expose-api/)了解如何发布你的第一个API。

也可参考 [保护 API ](https://apisix.apache.org/zh/docs/apisix/tutorials/protect-api/)了解如何保护你的API。
