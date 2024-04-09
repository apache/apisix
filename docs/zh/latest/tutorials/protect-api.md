---
title: 保护 API
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

本文将为你介绍使用限流限速和安全插件保护你的 API。

## 概念介绍

### 插件

[Plugin](../terminology/plugin.md) 也称之为插件，它是扩展 APISIX 应用层能力的关键机制，也是在使用 APISIX 时最常用的资源对象。插件主要是在 HTTP 请求或响应生命周期期间执行的、针对请求的个性化策略。插件可以与路由、服务或消费者绑定。

:::note 注意

如果 [路由](../terminology/route.md)、[服务](../terminology/service.md)、[插件配置](../terminology/plugin-config.md) 或消费者都绑定了相同的插件，则只有一份插件配置会生效，插件配置的优先级由高到低顺序是：消费者 > 路由 > 插件配置 > 服务。同时在插件执行过程中也会涉及 6 个阶段，分别是 `rewrite`、`access`、`before_proxy`、`header_filter`、`body_filter` 和 `log`。

:::

## 前提条件

在进行该教程前，请确保你已经[公开服务](./expose-api.md)。

## 保护 API

在很多时候，我们的 API 并不是处于一个非常安全的状态，它随时会收到不正常的访问，一旦访问流量突增，可能就会导致你的 API 发生故障，产生不必要的损失。因此你可以通过速率限制保护你的 API 服务，限制非正常的访问请求，保障 API 服务的稳定运行。对此，我们可以使用如下方式进行：

1. 限制请求速率；
2. 限制单位时间内的请求数；
3. 延迟请求；
4. 拒绝客户端请求；
5. 限制响应数据的速率。

为了实现上述功能，APISIX 提供了多个限流限速的插件，包括 [limit-conn](../plugins/limit-conn.md)、[limit-count](../plugins/limit-count.md) 和 [limit-req](../plugins/limit-req.md)。

- `limit-conn` 插件主要用于限制客户端对服务的并发请求数。
- `limit-req` 插件使用漏桶算法限制对用户服务的请求速率。
- `limit-count` 插件主要用于在指定的时间范围内，限制每个客户端总请求个数。

接下来，我们将以 `limit-count` 插件为例，为你介绍如何通过限流限速插件保护你的 API。

1. 创建路由。

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
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
  "upstream_id": "1"
}'

```

以上配置中，使用了[公开服务](./expose-api.md)中创建的上游创建了一个 ID 为 `1` 的路由， ，并且启用了 `limit-count` 插件。该插件仅允许客户端在 60 秒内，访问上游服务 2 次，超过两次，则会返回 `503` 错误码。

2. 测试插件。

```shell

curl http://127.0.0.1:9080/index.html

```

使用上述命令连续访问三次后，则会出现如下错误。

```
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

返回上述结果，则表示 `limit-count` 插件已经配置成功。

## 流量控制插件

APISIX 除了提供限流限速的插件外，还提供了很多其他的关于 **traffic** 插件来满足实际场景的需求：

- [proxy-cache](../plugins/proxy-cache.md)：该插件提供缓存后端响应数据的能力，它可以和其他插件一起使用。该插件支持基于磁盘和内存的缓存。
- [request-validation](../plugins/request-validation.md)：该插件用于提前验证向上游服务转发的请求。
- [proxy-mirror](../plugins/proxy-mirror.md)：该插件提供了镜像客户端请求的能力。流量镜像是将线上真实流量拷贝到镜像服务中，以便在不影响线上服务的情况下，对线上流量或请求内容进行具体的分析。
- [api-breaker](../plugins/api-breaker.md)：该插件实现了 API 熔断功能，从而帮助我们保护上游业务服务。
- [traffic-split](../plugins/traffic-split.md)：该插件使用户可以逐步引导各个上游之间的流量百分比。，你可以使用该插件实现蓝绿发布，灰度发布。
- [request-id](../plugins/request-id.md)：该插件通过 APISIX 为每一个请求代理添加 `unique` ID 用于追踪 API 请求。
- [proxy-control](../plugins/proxy-control.md)：该插件能够动态地控制 NGINX 代理的相关行为。
- [client-control](../plugins/client-control.md)：该插件能够通过设置客户端请求体大小的上限来动态地控制 NGINX 处理客户端的请求。

## 更多操作

你可以参考[监控 API](./observe-your-api.md) 文档，对 APISIX 进行监控，日志采集，链路追踪等。
