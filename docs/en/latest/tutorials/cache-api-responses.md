---
title: Cache API responses
keywords:
  - API Gateway
  - Apache APISIX
  - Cache
  - Performance
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

This tutorial will focus primarily on handling caching at the API Gateway level by using Apache APISIX API Gateway and you will learn how to use proxy-caching plugin to improve response efficiency for your Web or Microservices API.

**Here is an overview of what we cover in this walkthrough:**

- ✔️ Caching in API Gateway
- ✔️ About [Apache APISIX API Gateway](https://apisix.apache.org/docs/apisix/getting-started/)
- ✔️ Run the demo project [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker)
- ✔️ Configure the [Proxy Cache](https://apisix.apache.org/docs/apisix/plugins/proxy-cache/) plugin
- ✔️ Validate Proxy Caching

## Improve performance with caching

When you are building an API, you want to keep it simple and fast. Once the concurrent need to read the same data increase, you'll face a few issues 😐 where you might be considering introducing **caching**:

- ❌ There is latency on some API requests which is noticeably affecting the user's experience.
- ❌ Fetching data from a database takes more time to respond.
- ❌ Availability of your API is threatened by the API's high throughput.
- ❌ There are some network failures in getting frequently accessed information from your API.

## Caching in API Gateway

[Caching](https://en.wikipedia.org/wiki/Cache_(computing)) is capable of storing and retrieving network requests and their corresponding responses. Caching happens at different levels in a web application:

- Edge caching or CDN
- Database caching
- Server caching (API caching)
- Browser caching

**Reverse Proxy Caching** is yet another caching mechanism that is usually implemented inside **API Gateway**. It can reduce the number of calls made to your endpoint and also improve the latency of requests to your API by caching a response from the upstream. If the API Gateway cache has a fresh copy of the requested resource, it uses that copy to satisfy the request directly instead of making a request to the endpoint. If the cached data is not found, the request travels to the intended upstream services (backend services).

## Apache APISIX API Gateway Proxy Caching

With the help of Apache APISIX, you can enable API caching with [proxy-cache](https://apisix.apache.org/docs/apisix/plugins/proxy-cache/) plugin🔌to cache your API endpoint's responses and enhance the performance. It can be used together with other Plugins too and currently supports disk-based caching. The data to be cached can be filtered with _response codes, request modes_, or more complex methods using the _no_cache_ and _cache_bypass_ attributes. You can specify cache expiration time or a memory capacity in the plugin configuration as well. Please, refer to other `proxy-cache` plugin's [attributes](https://apisix.apache.org/docs/apisix/plugins/proxy-cache/).

🙋🏼 With all this in mind, we'll look next at an example of using `proxy-cache` plugin offered by Apache APISIX and apply it for ASP.NET Core Web API with a single endpoint.

## Run the demo project

Until now, I assume that you have the demo project [apisix-dotnet-docker](https://github.com/Boburmirzo/apisix-dotnet-docker) is up and running. You can see the complete source code on **Github** and the instruction on how to build a multi-container **APISIX** via **Docker CLI**.

In the **ASP.NET Core project**, there is a simple API to get all products list from the service layer in [ProductsController.cs](https://github.com/Boburmirzo/apisix-dotnet-docker/blob/main/ProductApi/Controllers/ProductsController.cs) file.

Let's assume that this product list is usually updated only once a day and the endpoint receives repeated billions of requests every day to fetch the product list partially or all of them. In this scenario, using API caching technique with `proxy-cache` plugin might be really helpful🙌. For the demo purpose, we only enable caching for `GET` method.

> Ideally, `GET` requests should be cacheable by default - until a special condition arises.

## Configure the Proxy Cache Plugin

Now let's start with adding `proxy-cache` plugin to Apache APISIX declarative configuration file `config.yaml` in the project. Because in the current project, we have not registered yet the plugin we are going to use for this demo. We appended `proxy-cache` plugin's name to the end of plugins list:

``` yaml
plugins:
 - http-logger
 - ip-restriction
 …
 - proxy-cache
```

You can add your cache configuration in the same file if you need to specify values like _disk_size, memory_size_ as shown below:

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

Next, we can directly run `apisix reload` command to reload the latest plugin code without restarting Apache APISIX. See the command to reload the newly added plugin:

``` shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

Then, we run two more curl commands to configure an Upstream and Route for the `/api/products` endpoint. The following command creates a sample upstream (that's our API Server):

``` shell
curl "http://127.0.0.1:9080/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
 "type": "roundrobin",
 "nodes": {
 "productapi:80": 1
 }
}'
```

Next, we will add a new route with caching ability by setting `proxy-cache` plugin in `plugins` property and giving a reference to the upstream service by its unique id to forward requests to the API server:

``` shell
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d ' 
{
 "name": "Route for API Caching",
 "methods": ["GET"], 
 "uri": "/api/products", 
 "plugins": {
 "proxy-cache": {
 "cache_key": ["$uri", "-cache-id"],
 "cache_bypass": ["$arg_bypass"],
 "cache_method": ["GET"],
 "cache_http_status": [200],
 "hide_cache_headers": true,
 "no_cache": ["$arg_test"]
 }
 }, 
 "upstream_id": 1
}'
```

As you can see in the above configuration, we defined some plugin attributes that we want to cache only successful responses from the `GET` method of API.

## Validate Proxy Caching🙎

Finally, we can test the proxy caching if it is working as it is expected.

We will send multiple requests to the `/api/products` path and we should receive `HTTP 200 OK` response each time. However, the `Apisix-Cache-Status` in the response shows _MISS_ meaning that the response has not cached yet when the request hits the route for the first time. Now, if you make another request, you will see that you get a cached response with the caching indicator as _HIT_.

Now we can make an initial request:

``` shell
curl http://localhost:9080/api/products -i
```

The response looks like as below:

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: MISS
```

When you do the next call to the service, the route responds to the request with a cached response since it has already cached in the previous request:

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: HIT
```

Or if you try again to hit the endpoint after the time-to-live (TTL) period for the cache ends, you will get:

``` shell
HTTP/1.1 200 OK
…
Apisix-Cache-Status: EXPIRED
```

Excellent! We enabled caching for our API endpoint 😎

### Additional test case

💁🏼 Optionally, you can also add some delay in the Product controller code and measure response time properly with and without cache:

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

The `curl` command to check response time would be:

```
curl -i 'http://localhost:9080/api/products' -s -o /dev/null -w "Response time: %{time_starttransfer} seconds\n"
```

## What's next

As we learned, it is easy to configure and quick to set up API response caching for our ASP.NET Core WEB API with the help of Apache APISIX. It can reduce significantly the number of calls made to your endpoint and also improve the latency of requests to your API. There are other numerous built-in plugins available in Apache APISIX, you can check them on [Plugin Hub page](https://apisix.apache.org/plugins) and use them per your need.

## Recommended content

You can refer to [Expose API](./protect-api.md) to learn about how to expose your first API.

You can refer to [Protect API](./protect-api.md) to protect your API.
