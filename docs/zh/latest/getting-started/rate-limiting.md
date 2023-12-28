---
title: 限速
slug: /getting-started/rate-limiting
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/rate-limiting" />
</head>

> 本教程由 [API7.ai](https://api7.ai/) 编写。

APISIX 是一个统一的控制中心，它管理 API 和微服务的进出流量。除了客户端发来的合理的请求，还可能存在网络爬虫产生的不必要的流量，此外，网络攻击（比如 DDos）也可能产生非法请求。

APISIX 提供限速功能，通过限制在规定时间内发送到上游服务的请求数量来保护 APIs 和微服务。请求的计数在内存中完成，具有低延迟和高性能的特点。

<br />
<div style={{textAlign: 'center'}}>
<img src="https://static.apiseven.com/uploads/2023/02/20/l9G9Kq41_rate-limiting.png" alt="Routes Diagram" />
</div>
<br />

在本教程中，你将启用 `limit-count` 插件来限制传入流量的速率。

## 前置条件

1. 参考[入门指南](./README.md)完成 APISIX 的安装。
2. 完成[配置路由](./configure-routes.md#route-是什么)。

## 启用 Rate Limiting

在教程[配置路由](./configure-routes.md)中，我们已经创建了路由 `getting-started-ip`，我们通过 `PATCH` 方法为该路由增加 `limit-count` 插件：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/getting-started-ip" -X PATCH -d '
{
  "plugins": {
    "limit-count": {
        "count": 2,
        "time_window": 10,
        "rejected_code": 503
     }
  }
}'
```

如果增加插件成功，你将得到返回 `HTTP/1.1 201 Created`。上述配置将传入流量的速率限制为每 10 秒最多 2 个请求。

### 验证

我们同时生成 100 个请求来测试限速插件的效果。

```shell
count=$(seq 100 | xargs -I {} curl "http://127.0.0.1:9080/ip" -I -sL | grep "503" | wc -l); echo \"200\": $((100 - $count)), \"503\": $count
```

请求结果同预期一致：在这 100 个请求中，有 2 个请求发送成功（状态码为 `200`），其他请求均被拒绝（状态码为 `503`）。

```text
"200": 2, "503": 98
```

## 禁用 Rate Limiting

将参数设置 `_meta.disable` 为 `true`，即可禁用限速插件。

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/getting-started-ip" -X PATCH -d '
{
    "plugins": {
        "limit-count": {
            "_meta": {
                "disable": true
            }
        }
    }
}'
```

### 验证

我们再次同时生成 100 个请求来测试限速插件是否已被禁用：

```shell
count=$(seq 100 | xargs -i curl "http://127.0.0.1:9080/ip" -I -sL | grep "503" | wc -l); echo \"200\": $((100 - $count)), \"503\": $count
```

结果显示所有的请求均成功：

```text
"200": 100, "503": 0
```

## 更多

你可以使用 APISIX 的变量来配置限速插件的规则，比如 `$host` 和 `$uri`。此外，APISIX 也支持使用 Redis 集群进行限速配置，即通过 Redis 来进行计数。

## 下一步

恭喜你！你已经学习了如何配置限速插件，这也意味着你已经完成了所有的入门教程。

你可以继续学习其他文档来定制 APISIX，以满足你的生产环境需要。
