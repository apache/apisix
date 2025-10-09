---
title: prometheus
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Prometheus
description:  本文将介绍 prometheus 插件，以及将 APISIX 与 Prometheus 集成以进行指标收集和持续监控。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/prometheus" />
</head>

## 描述

`prometheus` 插件提供将 APISIX 与 Prometheus 集成的能力。

启用该插件后，APISIX 将开始收集相关指标，例如 API 请求和延迟，并以[基于文本的展示格式](https://prometheus.io/docs/instrumenting/exposition_formats/#exposition-formats)导出到 Prometheus。然后，您可以在 Prometheus 中创建事件监控和警报，以监控 API 网关和 API 的健康状况。

## 静态配置

默认情况下，已在默认配置文件 [`config.lua`](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua) 中对 `prometheus` 进行预配置。

要自定义这些值，请将相应的配置添加到 config.yaml 中。例如：

```yaml
plugin_attr:
  prometheus:                               # 插件：prometheus 属性
    export_uri: /apisix/prometheus/metrics  # 设置 Prometheus 指标端点的 URI。
    metric_prefix: apisix_                  # 设置 APISIX 生成的 Prometheus 指标的前缀。
    enable_export_server: true              # 启用 Prometheus 导出服务器。
    export_addr:                            # 设置 Prometheus 导出服务器的地址。
      ip: 127.0.0.1                         # 设置 IP。
      port: 9091                            # 设置端口。
    # metrics:                              # 为指标创建额外的标签。
    #  http_status:                         # 这些指标将以 `apisix_` 为前缀。
    #    extra_labels:                      # 设置 http_status 指标的额外标签。
    #      - upstream_addr: $upstream_addr
    #      - status: $upstream_status
    #    expire: 0                          # 指标的过期时间（秒）。
                                            # 0 表示指标不会过期。
    #  http_latency:
    #    extra_labels:                      # 设置 http_latency 指标的额外标签。
    #      - upstream_addr: $upstream_addr
    #    expire: 0                          # 指标的过期时间（秒）。
                                            # 0 表示指标不会过期。
    #  bandwidth:
    #    extra_labels:                      # 设置 bandwidth 指标的额外标签。
    #      - upstream_addr: $upstream_addr
    #    expire: 0                          # 指标的过期时间（秒）。
                                            # 0 表示指标不会过期。
    # default_buckets:                      # 设置 `http_latency` 指标直方图的默认桶。
    #   - 10
    #   - 50
    #   - 100
    #   - 200
    #   - 500
    #   - 1000
    #   - 2000
    #   - 5000
    #   - 10000
    #   - 30000
    #   - 60000
    #   - 500
```

您可以使用 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)创建 `extra_labels`。请参见[为指标添加额外标签](#为指标添加额外标签)。

重新加载 APISIX 以使更改生效。

## 属性

| 名称         | 类型     | 必选项 | 默认值 |  描述                                                  |
| ------------ | --------| ------ | ------ | ----------------------------------------------------- |
|prefer_name | boolean | 否     | False  | 当设置为 `true` 时，则在`prometheus` 指标中导出路由/服务名称而非它们的 `id`。 |

## 指标

Prometheus 中有不同类型的指标。要了解它们之间的区别，请参见[指标类型](https://prometheus.io/docs/concepts/metric_types/)。

以下是 `prometheus` 插件默认导出的指标。有关示例，请参见[获取 APISIX 指标](#获取 APISIX 指标)。请注意，一些指标，例如 `apisix_batch_process_entries`，如果没有数据，将不可见。

| 名称                    | 类型      | 描述                                                                                                                                                                   |
| ----------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| apisix_bandwidth        | counter   | APISIX 中每个服务消耗的总流量（字节）。                                                                                                                               |
| apisix_etcd_modify_indexes | gauge     | APISIX 键的 etcd 修改次数。                                                                                                                                          |
| apisix_batch_process_entries | gauge     | 发送数据时批处理中的剩余条目数，例如使用 `http logger` 和其他日志插件。                                                                                             |
| apisix_etcd_reachable   | gauge     | APISIX 是否可以访问 etcd。值为 `1` 表示可达，`0` 表示不可达。                                                                                                      |
| apisix_http_status      | counter   | 从上游服务返回的 HTTP 状态代码。                                                                                                                                     |
| apisix_http_requests_total | gauge     | 来自客户端的 HTTP 请求数量。                                                                                                                                         |
| apisix_nginx_http_current_connections | gauge     | 当前与客户端的连接数量。                                                                                                                                             |
| apisix_nginx_metric_errors_total | counter   | `nginx-lua-prometheus` 错误的总数。                                                                                                                                 |
| apisix_http_latency     | histogram | HTTP 请求延迟（毫秒）。                                                                                                                                               |
| apisix_node_info        | gauge     | APISIX 节点的信息，例如主机名和当前的 APISIX 版本号。                                                                                                                                       |
| apisix_shared_dict_capacity_bytes | gauge     | [NGINX 共享字典](https://github.com/openresty/lua-nginx-module#ngxshareddict) 的总容量。                                                                                     |
| apisix_shared_dict_free_space_bytes | gauge     | [NGINX 共享字典](https://github.com/openresty/lua-nginx-module#ngxshareddict) 中剩余的空间。                                                                                   |
| apisix_upstream_status   | gauge     | 上游节点的健康检查状态，如果在上游配置了健康检查，则可用。值为 `1` 表示健康，`0` 表示不健康。                                                                                   |
| apisix_stream_connection_total | counter   | 每个 Stream Route 处理的总连接数。                                                                                                                                         |

## 标签

[标签](https://prometheus.io/docs/practices/naming/#labels) 是指标的属性，用于区分指标。

例如，`apisix_http_status` 指标可以使用 `route` 信息进行标记，以识别 HTTP 状态的来源路由。

以下是 APISIX 指标的非详尽标签及其描述。

### `apisix_http_status` 的标签

以下标签用于区分 `apisix_http_status` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| code   | 上游节点返回的 HTTP 响应代码。                                                                                       |
| route  | HTTP 状态来源的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| matched_uri | 匹配请求的路由 URI。如果请求不匹配任何路由，则默认为空字符串。                                                       |
| matched_host | 匹配请求的路由主机。如果请求不匹配任何路由，或路由未配置主机，则默认为空字符串。                                     |
| service | HTTP 状态来源的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 上游节点的 IP 地址。                                                                                                   |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### `apisix_bandwidth` 的标签

以下标签用于区分 `apisix_bandwidth` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| type   | 流量类型，`egress` 或 `ingress`。                                                                                     |
| route  | 带宽对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| service | 带宽对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 上游节点的 IP 地址。                                                                                                   |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### Labels for `apisix_llm_latency`

| Name | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |                                                                                             |
| route_id      | 带宽对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。                        |
| service_id    | 带宽对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 上游节点的 IP 地址。                                                                                          |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### Labels for `apisix_llm_active_connections`

| Name | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route      | Name of the Route that bandwidth corresponds to. Default to an empty string if a request does not match any Route.                                                                                 |
| route_id      | 带宽对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。                         |
| matched_uri | 匹配请求的路由 URI。如果请求不匹配任何路由，则默认为空字符串。                                                       |
| matched_host | 匹配请求的路由主机。如果请求不匹配任何路由，或路由未配置主机，则默认为空字符串。                                     |
| service    | Name of the Service that bandwidth corresponds to. Default to the configured value of host on the Route if the matched Route does not belong to any Service. |
| service_id    |  带宽对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 上游节点的 IP 地址。                                                                                          |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### Labels for `apisix_llm_completion_tokens`

| Name | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |                                                                                             |
| route_id      | 带宽对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。                         |
| service_id    |  带宽对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 上游节点的 IP 地址。                                                                                          |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### Labels for `apisix_llm_prompt_tokens`

| Name | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |                                                                                             |
| route_id      | 带宽对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。                         |
| service_id    |  带宽对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 上游节点的 IP 地址。                                                                                          |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

### `apisix_http_latency` 的标签

以下标签用于区分 `apisix_http_latency` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| type   | 延迟类型。有关详细信息，请参见 [延迟类型](#延迟类型)。                                                            |
| route  | 延迟对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| service | 延迟对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与延迟关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 与延迟关联的上游节点的 IP 地址。                                                                                     |
| request_type       | traditional_http / ai_chat / ai_stream                                                                                          |
| llm_model       | 对于非传统的 http 请求，llm 模型的名称                                                                                          |

#### 延迟类型

`apisix_http_latency` 可以标记为以下三种类型之一：

* `request` 表示从客户端读取第一个字节到最后一个字节发送到客户端之间的时间。

* `upstream` 表示等待上游服务响应的时间。

* `apisix` 表示 `request` 延迟与 `upstream` 延迟之间的差异。

换句话说，APISIX 延迟不仅归因于 Lua 处理。应理解为：

```text
APISIX 延迟
  = 下游请求时间 - 上游响应时间
  = 下游流量延迟 + NGINX 延迟
```

### `apisix_upstream_status` 的标签

以下标签用于区分 `apisix_upstream_status` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| name   | 与健康检查配置的上游对应的资源 ID，例如 `/apisix/routes/1` 和 `/apisix/upstreams/1`。                              |
| ip     | 上游节点的 IP 地址。                                                                                                   |
| port   | 节点的端口号。                                                                                                         |

## 示例

以下示例演示如何在不同场景中使用 `prometheus` 插件。

### 获取 APISIX 指标

以下示例演示如何从 APISIX 获取指标。

默认的 Prometheus 指标端点和其他与 Prometheus 相关的配置可以在 [静态配置](#静态配置) 中找到。如果您希望自定义这些配置，更新 `config.yaml` 并重新加载 APISIX。

如果您在容器化环境中部署 APISIX，并希望外部访问 Prometheus 指标端点，请按如下方式更新配置文件并重新加载 APISIX：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    export_addr:
      ip: 0.0.0.0
```

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

您应该看到类似以下的输出：

```text
# HELP apisix_bandwidth Total bandwidth in bytes consumed per Service in Apisix
# TYPE apisix_bandwidth counter
apisix_bandwidth{type="egress",route="",service="",consumer="",node="",request_type="traditional_http",request_llm_model="",llm_model=""} 8417
apisix_bandwidth{type="egress",route="1",service="",consumer="",node="127.0.0.1",request_type="traditional_http",request_llm_model="",llm_model=""} 1420
apisix_bandwidth{type="egress",route="2",service="",consumer="",node="127.0.0.1",request_type="traditional_http",request_llm_model="",llm_model=""} 1420
apisix_bandwidth{type="ingress",route="",service="",consumer="",node="",request_type="traditional_http",request_llm_model="",llm_model=""} 189
apisix_bandwidth{type="ingress",route="1",service="",consumer="",node="127.0.0.1",request_type="traditional_http",request_llm_model="",llm_model=""} 332
apisix_bandwidth{type="ingress",route="2",service="",consumer="",node="127.0.0.1",request_type="traditional_http",request_llm_model="",llm_model=""} 332
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 0
...
```

### 在公共 API 端点上公开 APISIX 指标

以下示例演示如何禁用默认情况下在端口 `9091` 上公开的 Prometheus 导出服务器，并在 APISIX 用于监听其他客户端请求的公共 API 端点上公开 APISIX Prometheus 指标。

在配置文件中禁用 Prometheus 导出服务器，并重新加载 APISIX 以使更改生效：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

接下来，使用 [`public-api`](../../../zh/latest/plugins/public-api.md) 插件创建一个路由，并为 APISIX 指标公开一个公共 API 端点：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/prometheus-metrics" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/apisix/prometheus/metrics",
    "plugins": {
      "public-api": {}
    }
  }'
```

向新指标端点发送请求以进行验证：

```shell
curl "http://127.0.0.1:9080/apisix/prometheus/metrics"
```

您应该看到类似以下的输出：

```text
# HELP apisix_http_requests_total 自 APISIX 启动以来客户端请求的总数。
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 1
# HELP apisix_nginx_http_current_connections 当前 HTTP 连接数量。
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 1
apisix_nginx_http_current_connections{state="active"} 1
apisix_nginx_http_current_connections{state="handled"} 1
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 0
apisix_nginx_http_current_connections{state="writing"} 1
...
```

### 监控上游健康状态

以下示例演示如何监控上游节点的健康状态。

使用 `prometheus` 插件创建一个路由，并配置上游的主动健康检查：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "prometheus-route",
    "uri": "/get",
    "plugins": {
      "prometheus": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1,
        "127.0.0.1:20001": 1
      },
      "checks": {
        "active": {
          "timeout": 5,
          "http_path": "/status",
          "healthy": {
            "interval": 2,
            "successes": 1
          },
          "unhealthy": {
            "interval": 1,
            "http_failures": 2
          }
        },
        "passive": {
          "healthy": {
            "http_statuses": [200, 201],
            "successes": 3
          },
          "unhealthy": {
            "http_statuses": [500],
            "http_failures": 3,
            "tcp_failures": 3
          }
        }
      }
    }
  }'
```

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

您应该看到类似以下的输出：

```text
# HELP apisix_upstream_status 上游健康检查的状态
# TYPE apisix_upstream_status gauge
apisix_upstream_status{name="/apisix/routes/1",ip="54.237.103.220",port="80"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="20001"} 0
```

这显示上游节点 `httpbin.org:80` 是健康的，而上游节点 `127.0.0.1:20001` 是不健康的。

### 为指标添加额外标签

以下示例演示如何为指标添加额外标签，并在标签值中使用 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。

目前，仅以下指标支持额外标签：

* apisix_http_status
* apisix_http_latency
* apisix_bandwidth

在配置文件中包含以下配置以为指标添加标签，并重新加载 APISIX 以使更改生效：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:                                # 插件：prometheus
    metrics:                                 # 根据 NGINX 变量创建额外标签。
      http_status:
        extra_labels:                        # 设置 `http_status` 指标的额外标签。
          - upstream_addr: $upstream_addr    # 添加一个额外的 `upstream_addr` 标签，其值为 NGINX 变量 $upstream_addr。
          - route_name: $route_name          # 添加一个额外的 `route_name` 标签，其值为 APISIX 变量 $route_name。
```

请注意，如果您在标签值中定义了一个变量，但它与任何现有的 [APISIX 变量](https://apisix.apache.org/zh/docs/apisix/apisix-variable/) 和 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) 不对应，则标签值将默认为空字符串。

使用 `prometheus` 插件创建一个路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "prometheus-route",
    "name": "extra-label",
    "plugins": {
      "prometheus": {}
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送请求以进行验证：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该看到 `HTTP/1.1 200 OK` 的响应。

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

您应该看到类似以下的输出：

```text
# HELP apisix_http_status APISIX 中每个服务的 HTTP 状态代码
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="1",matched_uri="/get",matched_host="",service="",consumer="",node="54.237.103.220",upstream_addr="54.237.103.220:80",route_name="extra-label"} 1
```

### 使用 Prometheus 监控 TCP/UDP 流量

以下示例演示如何在 APISIX 中收集 TCP/UDP 流量指标。

在 `config.yaml` 中包含以下配置以启用 Stream proxy 和 `prometheus` 插件。重新加载 APISIX 以使更改生效：

```yaml title="conf/config.yaml"
apisix:
  proxy_mode: http&stream   # 启用 L4 和 L7 代理
  stream_proxy:             # 配置 L4 代理
    tcp:
      - 9100                # 设置 TCP 代理监听端口
    udp:
      - 9200                # 设置 UDP 代理监听端口

stream_plugins:
  - prometheus              # 为 stream proxy 启用 prometheus
```

使用 `prometheus` 插件创建一个 Stream Route：

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "prometheus": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向该 Stream Route 发送请求以进行验证：

```shell
curl -i "http://127.0.0.1:9100"
```

您应该看到 `HTTP/1.1 200 OK` 的响应。

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

您应该看到类似以下的输出：

```text
# HELP apisix_stream_connection_total APISIX 中每个 Stream Route 处理的总连接数
# TYPE apisix_stream_connection_total counter
apisix_stream_connection_total{route="1"} 1
```
