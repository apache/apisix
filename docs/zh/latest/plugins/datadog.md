---
title: datadog
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Datadog
description: datadog 插件与 Datadog 集成，将指标批量发送到 DogStatsD，助力 API 监控与性能追踪。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/datadog" />
</head>

## 描述

`datadog` 插件支持与 [Datadog](https://www.datadoghq.com/) 集成。Datadog 是云应用中最常用的可观测性服务之一。启用后，插件通过 UDP 协议将指标推送到与 [Datadog agent](https://docs.datadoghq.com/agent/) 捆绑的 [DogStatsD](https://docs.datadoghq.com/developers/dogstatsd/?tab=hostagent) 服务器。

该插件支持通过 UDP 将指标以批量方式推送到外部 Datadog 代理。数据可能需要一段时间才能被接收，会在[批处理器](../batch-processor.md)的定时器到期后自动发送。

## 属性

| 名称             | 类型    | 必选项 | 默认值  | 有效值         | 描述                                                                                               |
| ---------------- | ------- | ------ | ------- | -------------- | -------------------------------------------------------------------------------------------------- |
| prefer_name      | boolean | 否     | true    | [true, false]  | 如果为 `true`，在指标标签中导出路由/服务名称而非 ID。                                              |
| include_path     | boolean | 否     | false   | [true, false]  | 如果为 `true`，在指标标签中包含路径模式。                                                          |
| include_method   | boolean | 否     | false   | [true, false]  | 如果为 `true`，在指标标签中包含 HTTP 方法。                                                        |
| constant_tags    | array   | 否     | []      |                | 附加到该路由所有指标的静态键值标签，便于按信号对指标进行分组。                                     |
| batch_max_size   | integer | 否     | 1000    | [1,...]        | 每个批次允许的最大日志条目数。达到后立即发送至 Datadog agent。设置为 `1` 表示立即处理。            |
| inactive_timeout | integer | 否     | 5       | [1,...]        | 等待新条目的最长时间（秒），超过则发送批次。该值应小于 `buffer_duration`。                         |
| buffer_duration  | integer | 否     | 60      | [1,...]        | 从最早条目起允许的最长缓冲时间（秒），超过则发送批次。                                             |
| retry_delay      | integer | 否     | 1       | [0,...]        | 批次发送失败后重试的时间间隔，单位为秒。                                                           |
| max_retry_count  | integer | 否     | 60      | [0,...]        | 丢弃条目前允许的最大重试次数。                                                                     |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据），避免频繁提交数据。默认情况下，批处理器每 `5` 秒或队列中数据达到 `1000` 条时提交一次。详情及自定义配置请参考[批处理器](../batch-processor.md#配置)。

## 插件元数据

可通过插件元数据配置该插件。

| 名称          | 类型    | 必选项 | 默认值              | 描述                                                                                                                                   |
| ------------- | ------- | ------ | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| host          | string  | 否     | "127.0.0.1"         | DogStatsD 服务器主机地址。                                                                                                             |
| port          | integer | 否     | 8125                | DogStatsD 服务器端口。                                                                                                                 |
| namespace     | string  | 否     | "apisix"            | APISIX agent 发送的所有自定义指标的前缀。有助于在指标图中定位实体，例如 `apisix.request.counter`。                                    |
| constant_tags | array   | 否     | [ "source:apisix" ] | 嵌入到生成指标中的静态标签，便于按信号对指标进行分组。详见[标签定义](https://docs.datadoghq.com/getting_started/tagging/#defining-tags)。 |

## 指标

插件默认导出以下指标。

所有指标均以元数据中配置的 `namespace` 为前缀。例如，若 `namespace` 设置为 `apisix`，则 `request.counter` 指标在 Datadog 中会导出为 `apisix.request.counter`。

| 名称             | StatsD 类型 | 描述                                                       |
| ---------------- | ----------- | ---------------------------------------------------------- |
| request.counter  | Counter     | 收到的请求数量。                                           |
| request.latency  | Histogram   | 处理请求所需时间，单位为毫秒。                             |
| upstream.latency | Histogram   | 代理请求到上游服务器并收到响应所需时间，单位为毫秒。       |
| apisix.latency   | Histogram   | APISIX agent 处理请求所需时间，单位为毫秒。                |
| ingress.size     | Timer       | 请求体大小，单位为字节。                                   |
| egress.size      | Timer       | 响应体大小，单位为字节。                                   |

## 标签

插件在导出指标时附带以下[标签](https://docs.datadoghq.com/getting_started/tagging)。如果某个标签没有合适的值，该标签将被省略。

| 名称                  | 描述                                                                                                           |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| route_name            | 路由名称。如果不存在或 `prefer_name` 为 false，则回退到路由 ID。                                               |
| service_name          | 服务名称。如果不存在或 `prefer_name` 为 false，则回退到服务 ID。                                               |
| consumer              | 若路由关联了消费者，则为消费者的用户名。                                                                       |
| balancer_ip           | 处理当前请求的上游负载均衡器 IP 地址。                                                                         |
| response_status       | HTTP 响应状态码，例如 `201`、`404` 或 `503`。                                                                  |
| response_status_class | HTTP 响应状态码类别，例如 `2xx`、`4xx` 或 `5xx`。APISIX 3.14.0 及以上版本支持。                               |
| scheme                | 请求协议，例如 HTTP 和 gRPC。                                                                                  |
| path                  | HTTP 路径模式。仅当 `include_path` 为 `true` 时可用。APISIX 3.14.0 及以上版本支持。                           |
| method                | HTTP 方法。仅当 `include_method` 为 `true` 时可用。APISIX 3.14.0 及以上版本支持。                             |

## 使用示例

以下示例演示了 `datadog` 插件在不同场景下的配置方式。

开始前，请确保已安装 [Datadog agent](https://docs.datadoghq.com/agent/)，它负责收集受监控对象的事件和指标并发送到 Datadog。

使用你的 API 密钥、Datadog 站点和主机名启动 Datadog agent。将 `DD_DOGSTATSD_NON_LOCAL_TRAFFIC` 设为 `true` 以接收来自其他容器的 DogStatsD 数据包：

```shell
docker run -d \
  --name dogstatsd-agent \
  -e DD_API_KEY=<your-api-key> \
  -e DD_SITE="us5.datadoghq.com" \
  -e DD_HOSTNAME=apisix.quickstart \
  -e DD_DOGSTATSD_NON_LOCAL_TRAFFIC=true \
  -p 8125:8125/udp \
  datadog/dogstatsd:latest
```

你可以通过 `DD_` 前缀的环境变量配置 agent 的主配置文件 `datadog.yaml` 中的大多数选项。更多信息请参阅 [agent 环境变量](https://docs.datadoghq.com/agent/guide/environment-variables)。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 更新 Datadog Agent 地址及元数据

默认情况下，插件期望 DogStatsD 服务器在 `127.0.0.1:8125` 可用。如需自定义地址及其他元数据，请更新插件元数据。将主机设置为你的 Datadog agent 地址，端口设置为 agent 监听端口，命名空间用于前缀所有指标，并可添加常量标签：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/datadog" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "host": "192.168.0.90",
    "port": 8125,
    "namespace": "apisix",
    "constant_tags": [
      "source:apisix",
      "service:custom"
    ]
  }'
```

如需恢复默认配置，发送空 body 的请求到 `datadog` 插件元数据接口：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/datadog" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{}'
```

### 监控路由指标

以下示例演示如何将特定路由的指标发送到 Datadog。

创建一个启用 `datadog` 插件的路由。将 `batch_max_size` 设为 `1` 以立即发送每条指标，将 `max_retry_count` 设为 `0` 以禁止失败重试：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "datadog-route",
    "uri": "/anything",
    "plugins": {
      "datadog": {
        "batch_max_size": 1,
        "max_retry_count": 0
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送几条请求：

```shell
curl "http://127.0.0.1:9080/anything"
```

在 Datadog 中，从左侧菜单选择**指标**，进入**资源管理器**，选择 `apisix.ingress.size.count` 指标，可以看到计数反映了已生成的请求数量。
