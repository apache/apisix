---
title: 负载均衡
keywords:
  - API 网关
  - Apache APISIX
  - 负载均衡
  - Load Balancing
description: 本文介绍了 APISIX 支持的四种负载均衡算法及其使用方法。
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

APISIX 支持配置加权轮询、一致性哈希、最少连接数和指数移动平均四种负载均衡算法。除此之外，你还可以在 balancer 阶段使用自定义负载均衡算法。

在配置上游时，可以通过 `type` 参数用来指定负载均衡算法，默认为加权轮询算法。更多信息，请参考 [Admin API 的 Upstream 对象](../admin-api.md#upstream)。

## 加权轮询（Round Robin）

轮询算法是最简单的负载均衡算法，其原理是将用户的请求依次分配给内部服务器，从第一个服务器开始直至最后一个服务器结束，所有服务器处理的请求数量是一致的。而加权轮询是在基本的轮询调度上，给每个节点赋值权重，节点的被调度比例等于权重比例，权重越大，被调度的次数越多。

### 使用场景

在实际生产环境中，上游集群会部署在不同性能的服务器上，如果采用基本的轮询调度，每台服务器被调度的比例是相同的，此时将会产生一个问题，高性能的服务器无法发挥性能的优势来承载更多的流量，低性能的服务器可能会过度承载流量而延迟显著甚至导致宕机。因此就要求用户把集群部署在相同性能的服务器上，才能最大程度上发挥服务器的性能，但是在实际环境中是无法实现的。

加权轮询的出现就是为了解决上述问题。在使用加权轮询算法时，用户可以根据上游服务器的性能，或者其他需求，设置上游节点被调度的比例。通过以上介绍可以看出，加权轮询算法适用于 HTTP 短连接服务。

### 特点

普通的加权轮询在调用上有一定的不足，比如 `A，B，C` 三台服务器的负载能力比例是 `3:2:1`，配置的权重分别是 3，2，1，可能会产生这样的调度顺序：{A，A，A，B，B，C}。

这样的调度顺序会出现一个问题，某个节点会在短时间内被集中调度，造成该节点负载过高，而不被调度时候负载很低，因此在观测时可以看到有规律的流量峰谷。

然而 APISIX 中使用的是平滑的加权轮询算法，短时间内的调度不会集中在同一个高权重节点上。

## 一致性哈希（CHash）

一致性哈希通过构造哈希环，根据客户端请求中的 key，用哈希算法计算出映射的上游节点。在同一个上游对象中，相同的 `key` 永远返回相同的上游节点。

### 使用场景

在使用 APISIX 时，有时候需要保证会话粘滞——将有相同特征的请求转发到同一个上游节点，因为这些具有相同特征的请求很可能来自同一个用户，需要在同一个上游节点中处理。
传统的负载均衡算法无法实现这一场景，此时你可以使用一致性哈希算法实现上述场景。因为一致性哈希算法可以根据发起请求的客户端 IP，或者请求参数中的某个值进行分配，将相同特征的请求分配到同一个上游节点。例如：

- Cookie 或 Session→身份
- IP→地理

一致性哈希负载策略也适合用在上游为分布式集群的场景中，它可以避免数据倾斜，允许将大量请求分配到少数节点上。

### 特点

APISIX 中的一致性哈希可以根据 NGINX 内置变量来指定 key，目前支持的 NGINX 内置变量有 `uri`，`server_name`，`server_addr`，`request_uri`，`remote_port`，`remote_addr`，`query_string`，`host`、`hostname`，`arg_***`，其中 `arg_***` 是来自 URL 的请求参数。

以下示例展示了 APISIX 一致性哈希算法的具体用法。创建一个路由并进行如下配置，配置的 `key` 是 `remote_addr`，即客户端 IP。可以观察当客户端 IP 始终相同时，请求是否会被代理到不同的上游节点。

:::note 注意

使用一致性哈希负载均衡算法时，建议上游节点的权重保持一致，防止权重不同干扰一致性哈希算法的结果。

哈希算法使用是库为 [lua-resty-chash](https://github.com/openresty/lua-resty-balancer)。

:::

## 加权最少连接数

最少连接数算法是一种智能、动态的负载均衡算法，主要是根据上游中每个节点的当前连接数决定将请求转发至哪个节点，即每次都将请求转发给当前存在最少并发连接的节点。

加权最少连接数是指选择 `(active_conn + 1) / weight` 最小的节点。通常，权重大且并发连接数最少的上游节点，将会被优先调用。

:::note 注意

`active_conn` 概念与 NGINX 中概念相同，表示当前正在被请求使用的连接。

:::

### 使用场景

在实际场景中，同一个上游节点会提供很多业务逻辑不同的 API，因此处理请求所消耗的时间也各不相同。在服务运行过程中，如果上游中的某个 API 突然涌入大量请求，则会出现延迟过高的情况。

从 APISIX 的角度出发，上游节点处理请求越快，则 APISIX 与该节点之间的 active_conn 数越少。因为请求被该节点快速处理，并且连接被释放了。

随着运行时间的持续增加，如果有些请求消耗了较长的处理时间，会导致该请求所在的上游节点负载较高。因此动态地根据请求处理时间（对于 APISIX 来说就是当前正在被请求使用的连接），把请求转发到 active_conn 较少的上游节点，可以避免大量耗时的请求堆积在高负载节点，从而达到优化负载均衡的效果。

此算法适用于需要长时间处理的请求服务，每个请求所占用的后端时间相差较大的场景。即长连接服务。

### 特点

加权最少连接数算法可以根据上游节点的负载情况动态分发请求，因此服务器性能强，处理请求速度快，积压请求少的上游节点可以承担更多的请求，反之则分配更少的请求。以此保证上游节点整体的稳定性，同时将请求合理地分配到每一个节点中，避免因节点负载过高而导致响应慢乃至宕机。

## 指数移动平均（EWMA）

指数移动平均算法会选择延迟最小的节点进行负载。指数移动平均是根据 [EWMA](https://en.wikipedia.org/wiki/EWMA_chart) 公式，用滑动窗口来计算窗口时间内某个节点的 EWMA 函数值，作为本次请求延迟的预测值。

### 使用场景

在延迟敏感的场景中，EWMA 负载均衡策略是最合适的选择。

- 当出现网络抖动时，延迟较大，EWMA 算法可以动态调小窗口时间，快速感知到抖动存在，EWMA 函数值接近网络抖动时的真实值；
- 当网络恢复稳定后，延迟较小，EWMA 算法可以动态调大窗口时间，EWMA 函数值平稳恢复到正常水平。

### 特点

APISIX 中用 P2C 优化了 EWMA 负载均衡策略，P2C 方式会随机选择两个节点，然后选择其中 EWMA 函数值最低的节点，以达到局部最优解。

## 预备节点

APISIX 支持配置预备节点。在配置节点时，可以配置其优先级属性。只有在所有高优先级的节点均不可用时，APISIX 才会使用低优先级的节点。

由于节点默认的优先级是 `0`，我们可以配置负优先级的节点作为预备节点。

### 使用示例

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": [
            {"host": "127.0.0.1", "port": 8081, "weight": 2000},
            {"host": "127.0.0.1", "port": 8082, "weight": 1, "priority": -1}
        ],
        ……
    }
}
```

如上所示，127.0.0.1:8082 节点仅在 127.0.0.1:8081 明确不可用或被尝试使用过后，才会被选择。因此，它是 `127.0.0.1:8081` 的预备节点。

## 使用示例

以下示例展示了 APISIX 一致性哈希算法的具体使用方法。创建一个路由并进行如下配置，配置的 `key` 是 `remote_addr`，即客户端 IP。可以观察当客户端 IP 始终相同时，请求是否会被代理到不同的上游节点。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/index.html",
    "upstream":{
        "nodes":{
            "127.0.0.1:8081":1,
            "127.0.0.1:8082":1,
            "127.0.0.1:8083":1
        },
        "key": "remote_addr",
        "type":"chash"
    }
}'
```

上述代码表示，该路由的负载均衡策略为 `"type":"chash"`，其中 key 为 `remote_addr`。更多详情，请参考[Admin API](../admin-api.md#upstream)。

使用如下命令请求 `12` 次：

```shell
curl 127.0.0.1:9080/index.html
```

返回结果如下：

```shell
8083,8083,8083,8083,8083,8083,8083,8083,8083,8083,8083,8083
```
