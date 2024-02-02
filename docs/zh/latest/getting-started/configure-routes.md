---
title: 配置路由
slug: /getting-started/configure-routes
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/configure-routes" />
</head>

> 本教程由 [API7.ai](https://api7.ai/) 编写。

Apache APISIX 使用 _routes_ 来提供灵活的网关管理功能，在一个请求中，_routes_ 包含了访问路径和上游目标等信息。

本教程将引导你创建一个 route 并验证它，你可以参考以下步骤：

1. 创建一个指向 [httpbin.org](http://httpbin.org)的 _upstream_。
2. 使用 _cURL_ 发送一个请求，了解 APISIX 的代理和转发请求机制。

## Route 是什么

Route（也称之为路由）是访问上游目标的路径，在 [Apache APISIX](https://api7.ai/apisix) 中，Route 首先通过预定的规则来匹配客户端请求，然后加载和执行相应的插件，最后将请求转发至特定的 Upstream。

在 APISIX 中，一个最简单的 Route 仅由匹配路径和 Upstream 地址两个信息组成。

## Upstream 是什么

Upstream（也称之为上游）是一组具备相同功能的节点集合，它是对虚拟主机的抽象。Upstream 可以通过预先配置的规则对多个服务节点进行负载均衡。

## 前置条件

1. 参考[入门指南](./README.md)完成 APISIX 的安装。

## 创建路由

你可以创建一个路由，将客户端的请求转发至 [httpbin.org](http://httpbin.org)（这个网站能测试 HTTP 请求和响应的各种信息）。

通过下面的命令，你将创建一个路由，把请求`http://127.0.0.1:9080/ip` 转发至 [httpbin.org/ip](http://httpbin.org/ip)：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "getting-started-ip",
  "uri": "/ip",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

如果配置成功，将会返回 `HTTP/1.1 201 Created`。

## 验证

```shell
curl "http://127.0.0.1:9080/ip"
```

你将会得到类似下面的返回：

```text
{
  "origin": "183.94.122.205"
}
```

## 下一步

本教程创建的路由仅对应一个上游目标。在下个教程中，你将会学习如何配置多个上游目标的负载均衡。
