---
title: datadog
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

## 简介

`datadog` 是 Apache APISIX 内置的监控插件，可与 [Datadog](https://www.datadoghq.com/)（云应用最常用的监控和可观测性平台之一）无缝集成。`datadog` 插件支持对每个请求和响应周期进行多种指标参数的获取，这些指标参数基本反映了系统的行为和健康状况。

该插件通过 UDP 协议将其自定义指标推送给 DogStatsD 服务器，该服务器与 Datadog 代理捆绑在一起（关于如何安装 Datadog 代理，请参考[Agent](https://docs.datadoghq.com/agent/) ）。DogStatsD 基本上是 StatsD 协议的实现，它将收集到的 Apache APISIX 代理的自定义指标聚合成单个数据点，并发送到设置的 Datadog 服务器上。更多关于 DogStatsD 的信息，请参考 [DogStatsD](https://docs.datadoghq.com/developers/dogstatsd/?tab=hostagent) 。

`datadog` 插件具有将多个指标组成一个批处理并统一推送给外部 Datadog 代理的能力，并且可以重复使用同一个数据报套接字。如果没有收到日志数据，请耐心等待，它会在批处理程序中的定时器功能到期后自动发送日志。

关于 Apache APISIX 的批处理程序的更多信息，请参考 [Batch-Processor](../batch-processor.md#配置)

## 属性

| 名称             | 类型   | 必选项  | 默认值      | 有效值       | 描述                                                                                |
| -----------      | ------ | -----------  | -------      | -----       | ------------------------------------------------------------                               |
| prefer_name      | boolean | optional    | true         | true/false  | 如果设置为 "false"，将使用路由/服务的 ID，而不是带有度量标签的名称（默认）。   |

该插件支持使用批处理程序来聚集和处理条目（日志/数据）的批次。这就避免了插件频繁地提交数据，默认情况下，批处理程序每 `5` 秒或当队列中的数据达到 `1000` 时提交数据。有关信息或自定义批处理程序的参数设置，请参阅[批处理程序](../batch-processor.md#configuration) 配置部分。

## 元数据

| 名称        | 类型    | 必选项 |     默认值        | 有效值         | 描述                                                            |
| ----------- | ------  | ----------- |      -------       | -----         | ---------------------------------------------------------------------- |
| host        | string  | optional    |  "127.0.0.1"       |               | DogStatsD 服务器的主机地址                                      |
| port        | integer | optional    |    8125            |               | DogStatsD服务器的主机端口                                         |
| namespace   | string  | optional    |    "apisix"        |               | 由APISIX代理发送的所有自定义度量的前缀。对寻找指标图的实体很有帮助，例如：(apisix.request.counter)。                                        |
| constant_tags | array | optional    | [ "source:apisix" ] |              | 嵌入到生成指标中的静态标签。这对某些信号度量进行分组很有用。 |

要了解更多关于如何有效地编写标签，请访问[这里](https://docs.datadoghq.com/getting_started/tagging/#defining-tags)

## 输出指标

Apache APISIX 代理，对于每个请求响应周期，如果启用了 datadog 插件，就会向 DogStatsD 服务器输出以下指标。

| Metric Name               | StatsD Type   | Description               |
| -----------               | -----------   | -------                   |
| Request Counter           | Counter       | 收到的请求数量。   |
| Request Latency           | Histogram     | 处理该请求所需的时间（以毫秒为单位）。 |
| Upstream latency          | Histogram     | 代理请求到上游服务器直到收到响应所需的时间（以毫秒为单位）。 |
| APISIX Latency            | Histogram     | APISIX 代理处理该请求的时间（以毫秒为单位）。|
| Ingress Size              | Timer         | 以字节为单位的请求体大小。 |
| Egress Size               | Timer         | 以字节为单位的响应体大小。 |

这些指标将被发送到带有以下标签的 DogStatsD 代理。

> 如果一个标签没有合适的值，该标签将被直接省略。

- **route_name**：在路由模式定义中指定的名称，如果不存在或插件属性 `prefer_name` 被设置为 `false`，它将回退成路由 id 值。
- **service_name**：如果一个路由是用服务的抽象概念创建的，特定的服务 name/id（基于插件的 `prefer_name` 属性）将被使用。
- **consumer**：如果路由有一个链接的消费者，消费者的用户名将被添加为一个标签。
- **balancer_ip**：处理了当前请求的 Upstream 平衡器的IP。
- **response_status**：HTTP 响应状态代码。
- **scheme**：用于提出如 HTTP、gRPC、gRPCs 等请求的 Scheme。

## 如何启用

本小节介绍了如何为特定路由启用 `datadog` 插件。进行以下操作之前请确认您的 `datadog` 代理已经启动并正常运行

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "datadog": {}
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

现在，任何对 uri `/hello` 的请求都会生成上述指标并推送到 Datadog 代理的DogStatsD 服务器。

## 禁用插件

删除插件配置中相应的 json 配置以禁用 `datadog`。
APISIX 插件是支持热加载的，所以不用重新启动 APISIX，配置就能生效。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 自定义配置

在默认配置中，该插件希望 dogstatsd 服务在 `127.0.0.1:8125` 可用。如果你想更新配置，请更新插件的元数据。要了解更多关于 datadog 元数据的字段，请参阅[这里](#元数据)。

向 _/apisix/admin/plugin_metadata_ 端点发出请求，更新后的元数据如下。

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/datadog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "host": "172.168.45.29",
    "port": 8126,
    "constant_tags": [
        "source:apisix",
        "service:custom"
    ],
    "namespace": "apisix"
}'
```

这个 HTTP PUT 请求将更新元数据，后续指标将通过 UDP StatsD 推送到 `172.168.45.29:8126` 端点。一切都将被热加载，不需要重新启动Apache APISIX实例。

在这种情况下，如果你想把 datadog 元数据 schema 恢复到默认值，只需向同一个端点再发出一个 body 为空的 PUT 请求。举例如下：

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/datadog \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '{}'
```
