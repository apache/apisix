---
title: 负载均衡
slug: /getting-started/load-balancing
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/load-balancing" />
</head>

> 本教程由 [API7.ai](https://api7.ai/) 编写。

负载均衡管理客户端和服务端之间的流量。它决定由哪个服务来处理特定的请求，从而提高性能、可扩展性和可靠性。在设计需要处理大量流量的系统时，负载均衡是一个关键的考虑因素。

Apache APISIX 支持加权负载均衡算法，传入的流量按照预定顺序轮流分配给一组服务器的其中一个。

在本教程中，你将创建一个具有两个上游服务的路由，并且启用负载均衡来测试在两个服务之间的切换情况。

## 前置条件

1. 参考[入门指南](./README.md)完成 APISIX 的安装。
2. 了解 APISIX 中[路由及上游](./configure-routes.md#route-是什么)的概念。

## 启用负载均衡

创建一个具有两个上游服务的路由，访问 `/headers` 将被转发到 [httpbin.org](https://httpbin.org/headers) 和 [mock.api7.ai](https://mock.api7.ai/headers) 这两个上游服务，并且会返回请求头。

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "getting-started-headers",
  "uri": "/headers",
  "upstream" : {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:443": 1,
      "mock.api7.ai:443": 1
    },
    "pass_host": "node",
    "scheme": "https"
  }
}'
```

如果路由创建成功，你将会收到返回 `HTTP/1.1 201 Created`。

:::info

1. 将 `pass_host` 字段设置为 `node`，将传递请求头给上游。
2. 将 `scheme` 字段设置为 `https`，向上游发送请求时将启用 TLS。

:::

## 验证

这两个服务返回不同的数据。

`httpbin.org` 返回：

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.58.0",
    "X-Amzn-Trace-Id": "Root=1-63e34b15-19f666602f22591b525e1e80",
    "X-Forwarded-Host": "localhost"
  }
}
```

`mock.api7.ai` 返回：

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    "user-agent": "curl/7.58.0",
    "content-type": "application/json",
    "x-application-owner": "API7.ai"
  }
}
```

我们生成 100 个请求来测试负载均衡的效果：

```shell
hc=$(seq 100 | xargs -I {} curl "http://127.0.0.1:9080/headers" -sL | grep "httpbin" | wc -l); echo httpbin.org: $hc, mock.api7.ai: $((100 - $hc))
```

结果显示，请求几乎平均分配给这两个上游服务：

```text
httpbin.org: 51, mock.api7.ai: 49
```

## 下一步

你已经学习了如何配置负载均衡。在下个教程中，你将学习如何配置身份验证。
