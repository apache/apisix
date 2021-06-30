---
title: 快速入门指南
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

本指南旨在让大家入门 Apache APISIX，我们将配置一个对外提供公共 API 的服务，并由 API key 进行访问保护。

另外，我们将以下面的 `echo` 端点为例，它将返回我们传递的参数。

**Request**

```bash
$ curl --location --request GET "http://httpbin.org/get?foo1=bar1&foo2=bar2"
```

**Response**

```json
{
  "args": {
    "foo1": "bar1",
    "foo2": "bar2"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6088fe84-24f39487166cce1f0e41efc9"
  },
  "origin": "58.152.81.42",
  "url": "http://httpbin.org/get?foo1=bar1&foo2=bar2"
}
```

让我们来分析一下上面的请求 URL：

- Protocol: HTTP
- Port: 80
- Host: `httpbin.org`
- URI/Path: `/get`
- Query Parameters: foo1, foo2

## 前提

> 如果您已经安装了 Apache APISIX，请直接阅读 [第二步](getting-started.md#第二步:-创建一个-Route)

- 本指南使用 [Docker](https://www.docker.com/) 和 [Docker Compose](https://docs.docker.com/compose/) 来安装 Apache APISIX。
- `curl`：本指南使用 [curl](https://curl.se/docs/manpage.html) 命令行进行 API 测试，但是您也可以使用任何其它工具，例如 [Postman](https://www.postman.com/)。

## 第一步: 安装 Apache APISIX

得益于 Docker，我们可以通过执行以下命令来启动 Apache APISIX 并启用 [Admin API](./admin-api.md)。

```bash
$ git clone https://github.com/apache/apisix-docker.git
$ cd apisix-docker/example
$ docker-compose -p docker-apisix up -d
```

下载所需的所有文件将花费一些时间，这取决于您的网络，请耐心等待。下载完成后，我们可以使用 `curl` 访问 Admin API，以判断 Apache APISIX 是否成功启动。

```bash
# 注意：请在运行 Docker 的宿主机上执行 curl 命令。
$ curl "http://127.0.0.1:9080/apisix/admin/services/" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

我们期望获得以下返回数据：

```json
{
  "count":1,
  "action":"get",
  "node":{
    "key":"/apisix/services",
    "nodes":{},
    "dir":true
  }
}
```

## 第二步: 创建一个 Route

恭喜！您现在已经拥有一个运行中的 Apache APISIX 实例了！接下来，让我们来创建一个 Route。

### 在我们继续之前

您知道吗？Apache APISIX 提供了强大的 [Admin API](./admin-api.md) 和 [Dashboard](https://github.com/apache/apisix-dashboard) 可供我们使用，但在本指南中我们使用 Admin API 来做演示。

我们可以创建一个 [Route](./architecture-design/route.md) 并与后端服务（通常称之为上游： [Upstream](./architecture-design/upstream.md)）绑定，当一个 `请求（Request）` 到达 Apache APISIX 时，Apache APISIX 就会明白这个请求应该转发到哪个上游服务中。

Apache APISIX 是如何知道的呢？那是因为我们为 Route 对象配置了匹配规则。下面是一个 Route 配置示例：

```json
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/services/users/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
```

这条路由配置意味着，当它们满足下述的 **所有** 规则时，所有匹配的入站请求都将被转发到 `httpbin.org:80` 上游：

- 请求的 HTTP 方法为 `GET`;
- 请求头包含 `Host` 字段，且它的值为 `example.com`;
- 请求路径匹配 `/services/users/*`，`*` 意味着任意的子路径，例如 `/services/users/getAll?limit=10`。

当这条路由创建后，我们就可以使用 Apache APISIX 对外暴露的地址去访问后端服务（即上游）：

```bash
$ curl -i -X GET "http://{APISIX_BASE_URL}/services/users/getAll?limit=10" -H "Host: example.com"
```

这将会被 Apache APISIX 转发到 `http://httpbin.org:80/services/users/getAll?limit=10`。

### 创建一个上游（Upstream）

读完上一节，我们知道必须为 `路由` 设置 `上游`。只需执行下面的命令即可创建一个上游：

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

我们使用 `roundrobin` 作为负载均衡机制，并将 `httpbin.org:80` 设置为我们的上游目标（后端服务），其 ID 为 `1`。更多字段信息，请参阅 [Admin API](./admin-api.md)。

**注意：** 创建上游实际上并不是必需的，因为我们可以使用 [插件](./architecture-design/plugin.md) 拦截请求，然后直接响应。但在本指南中，我们假设需要设置至少一个上游。

### 路由与上游绑定

We just created an Upstream(Reference to our backend services), let's bind one Route with it!
我们刚刚创建了一个上游(引用我们的后端服务)，让我们为它绑定一个路由！

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "upstream_id": "1"
}'
```

就是这样！

### 验证

再次恭喜！我们已创建了路由与上游，并将它们进行了绑定。现在让我们访问 Apache APISIX 来测试这条已经创建的路由：

```bash
$ curl -i -X GET "http://127.0.0.1:9080/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

哇哦! 它将从我们的上游（实际是 `httpbin.org`）返回数据，结果符合预期！

## 进阶

### 身份验证

让我们来做一些有趣的事情，由于我们在第二步中创建的路由是公共的，**任何人** 都可以访问，现在我们希望只有 `John` 可以访问它。让我们使用 [消费者（Consumer）](./architecture-design/consumer.md) 和 [插件（Plugin）](./architecture-design/plugin.md) 来实现这个保护措施。

首先，让我们用 [key-auth](./plugins/key-auth.md) 插件创建一个 [消费者（Consumer）](./architecture-design/consumer.md) `John`，我们需要提供一个指定的密钥:

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/consumers" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "username": "john",
  "plugins": {
    "key-auth": {
      "key": "key-of-john"
    }
  }
}'
```

接下来，让我们绑定 `消费者（John）` 到路由上，我们仅仅需要为路由 **启用** [key-auth](./plugins/key-auth.md) 插件即可。

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "plugins": {
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

OK，现在当我们访问第二步创建的路由时，将会产生一个 **Unauthorized Error**（未经授权的错误）。让我们看看如何正确访问那个路由：

```bash
$ curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H 'apikey: superSecretAPIKey'
```

是的，仅仅添加了一个带有正确密钥的名为 `apikey` 的 `Header`！这样就可以保护任何的路由了。

### 为路由添加前缀

现在，假设您要向路由添加前缀（例如：samplePrefix），并且不想使用 `host` 头， 则可以使用 `proxy-rewrite` 插件来完成。

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/samplePrefix/get",
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": ["^/samplePrefix/get(.*)", "/get$1"]
    },
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

现在您可以使用以下命令来调用路由：

```bash
$ curl -i -X GET "http://127.0.0.1:9080/samplePrefix/get?param1=foo&param2=bar" -H "apikey: key-of-john"
```

### APISIX Dashboard（控制台）

Apache APISIX 提供了一个 [Dashboard](https://github.com/apache/apisix-dashboard)，让我们的操作更直观更轻松。

![Dashboard](../../assets/images/dashboard.jpeg)

### 故障排查

- 确保所需的所有端口（**默认的 9080/9443/2379**）未被其他系统/进程使用。

    下面是终止正在侦听特定端口（基于 unix 的系统）的进程的命令。

    ```bash
    $ sudo fuser -k 9443/tcp
    ```

- 如果 Docker 容器持续不断地重启/失败，请登录容器并观察日志以诊断问题。

    ```bash
    $ docker logs -f --tail container_id
    ```
