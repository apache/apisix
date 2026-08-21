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

启用该插件后，APISIX 将开始收集相关指标，例如 API 请求和延迟，并以[基于文本的展示格式](https://prometheus.io/docs/instrumenting/exposition_formats/#exposition-formats)导出到 Prometheus。然后，你可以在 Prometheus 中创建事件监控和警报，以监控 API 网关和 API 的健康状况。

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
    #   - 1
    #   - 2
    #   - 5
    #   - 10
    #   - 20
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
```

你可以使用 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)创建 `extra_labels`。请参见[为指标添加额外标签](#为指标添加额外标签)。

重新加载 APISIX 以使更改生效。

## 属性

| 名称         | 类型     | 必选项 | 默认值 |  描述                                                  |
| ------------ | --------| ------ | ------ | ----------------------------------------------------- |
|prefer_name | boolean | 否     | false  | 当设置为 `true` 时，则在`prometheus` 指标中导出路由/服务名称而非它们的 `id`。 |

## 元数据

你可以通过插件的[元数据（Plugin Metadata）](../terminology/plugin-metadata.md)进行配置。元数据通过 Admin API 动态设置，无需重启即可在运行时生效。

| 名称            | 类型   | 必选项 | 描述                                                                                                                                                                                                                                                              |
| --------------- | ------ | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| disabled_labels | object | 否     | 按指标配置的内置标签列表，列出的标签其值会被设置为空字符串 `""` 以降低指标基数。以指标名称作为键：`http_status`、`http_latency`、`bandwidth`、`llm_latency`、`llm_prompt_tokens`、`llm_completion_tokens`、`llm_active_connections`、`llm_prompt_tokens_dist`、`llm_completion_tokens_dist`、`ai_cache_hits_total`、`ai_cache_misses_total`、`ai_cache_bypasses_total`、`ai_cache_embedding_latency`。定义指标本身含义的结构性标签（`http_status` 的 `code`、`http_latency`、`bandwidth` 与 `llm_latency` 的 `type`、`ai_cache_hits_total` 的 `layer`）不可被禁用。 |

将标签值设置为 `""` 时，标签仍保留在指标 schema 中，因此现有的仪表盘、`absent()` 告警和 recording rule 都不受影响——只是将仅因这些标签而不同的高基数时间序列合并为一条。这在 Kubernetes 弹性伸缩等动态环境中尤其有用：此时上游节点 IP（`node` 标签）频繁变化，否则会很快撑爆 `prometheus-metrics` 共享字典。

示例请参见[通过禁用标签降低指标基数](#通过禁用标签降低指标基数)。

`request_llm_model` 标签来自客户端请求的模型。`llm_model` 标签表示实际使用的目标模型：优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。为了限制基数，APISIX 在记录前会将这两个标签值分别截断为 128 字节。如果你不需要按模型细分，可将 `request_llm_model` 和 `llm_model` 列入 LLM 指标的 `disabled_labels`，从而将其折叠为一条空值时间序列。

## 指标

Prometheus 中有不同类型的指标。要了解它们之间的区别，请参见[指标类型](https://prometheus.io/docs/concepts/metric_types/)。

`prometheus` 插件会注册以下指标。有关示例，请参见[获取 APISIX 指标](#获取 APISIX 指标)。只有对应数据源启用后，相关指标序列才会出现。例如，Stream 指标要求将 `prometheus` 启用为 Stream 插件，LLM 指标要求存在 AI 流量，AI 缓存指标要求启用 `ai-cache` 插件，而 `apisix_batch_process_entries` 只有在批处理插件产生数据后才会出现。

| 名称                    | 类型      | 描述                                                                                                                                                                   |
| ----------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| apisix_bandwidth        | counter   | APISIX 中每个服务消耗的总流量（字节）。                                                                                                                               |
| apisix_etcd_modify_indexes | gauge     | APISIX 键的 etcd 修改次数。                                                                                                                                          |
| apisix_batch_process_entries | gauge     | 发送数据时批处理中的剩余条目数，例如使用 `http logger` 和其他日志插件。                                                                                             |
| apisix_etcd_reachable   | gauge     | APISIX 是否可以访问 etcd。值为 `1` 表示可达，`0` 表示不可达。                                                                                                      |
| apisix_http_status      | counter   | 返回给客户端的 HTTP 状态代码。                                                                                                                                       |
| apisix_http_requests_total | gauge     | 来自客户端的 HTTP 请求数量。                                                                                                                                         |
| apisix_nginx_http_current_connections | gauge     | 当前与客户端的连接数量。                                                                                                                                             |
| apisix_nginx_metric_errors_total | counter   | `nginx-lua-prometheus` 错误的总数。                                                                                                                                 |
| apisix_http_latency     | histogram | HTTP 请求延迟（毫秒）。                                                                                                                                               |
| apisix_llm_latency      | histogram | LLM 请求延迟（毫秒），包括总延迟和首 token 延迟。                                                                                                                    |
| apisix_llm_prompt_tokens | counter  | LLM 请求消耗的 prompt token 总数。                                                                                                                                    |
| apisix_llm_completion_tokens | counter | LLM 请求生成的 completion token 总数。                                                                                                                             |
| apisix_llm_active_connections | gauge | 到 LLM 服务的活跃连接数。                                                                                                                                             |
| apisix_llm_prompt_tokens_dist | histogram | 每个 LLM 请求消耗的 prompt token 数量分布。                                                                                                                       |
| apisix_llm_completion_tokens_dist | histogram | 每个 LLM 请求生成的 completion token 数量分布。                                                                                                                 |
| apisix_ai_cache_hits_total | counter | AI 缓存命中总数，按缓存层区分。                                                                                                                                       |
| apisix_ai_cache_misses_total | counter | AI 缓存未命中总数。                                                                                                                                                  |
| apisix_ai_cache_bypasses_total | counter | 绕过 AI 缓存的请求总数。                                                                                                                                          |
| apisix_ai_cache_embedding_latency | histogram | AI 缓存 embedding 调用延迟（毫秒）。                                                                                                                           |
| apisix_node_info        | gauge     | APISIX 节点的信息，例如主机名和当前的 APISIX 版本号。                                                                                                                                       |
| apisix_shared_dict_capacity_bytes | gauge     | [NGINX 共享字典](https://github.com/openresty/lua-nginx-module#ngxshareddict) 的总容量。                                                                                     |
| apisix_shared_dict_free_space_bytes | gauge     | [NGINX 共享字典](https://github.com/openresty/lua-nginx-module#ngxshareddict) 中剩余的空间。                                                                                   |
| apisix_upstream_status   | gauge     | 上游节点的健康检查状态，如果在上游配置了健康检查，则可用。值为 `1` 表示健康，`0` 表示不健康。                                                                                   |
| apisix_stream_connection_total | counter   | 每个 Stream Route 处理的总连接数。                                                                                                                                         |
| apisix_stream_active_connections | gauge   | 当前正在代理的 Stream 会话数，按监听地址区分。同时覆盖 TCP 连接与 UDP 会话。                                                                                                 |
| apisix_stream_status          | counter   | 每条 Stream 会话结束时计数一次，按结束方式分类。                                                                                                                           |
| apisix_stream_bandwidth       | counter   | Stream 子系统代理的总流量（字节），按监听地址与方向区分。                                                                                                                   |

## 标签

[标签](https://prometheus.io/docs/practices/naming/#labels) 是指标的属性，用于区分指标。

例如，`apisix_http_status` 指标可以使用 `route` 信息进行标记，以识别 HTTP 状态的来源路由。

以下是 APISIX 指标的非详尽标签及其描述。

### `apisix_http_status` 的标签

以下标签用于区分 `apisix_http_status` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| code   | 返回给客户端的 HTTP 响应代码。                                                                                         |
| route  | HTTP 状态来源的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| matched_uri | 匹配请求的路由 URI。如果请求不匹配任何路由，则默认为空字符串。                                                       |
| matched_host | 匹配请求的路由主机。如果请求不匹配任何路由，或路由未配置主机，则默认为空字符串。                                     |
| service | HTTP 状态来源的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 上游节点的 IP 地址。                                                                                                   |
| request_type       | 请求类别：`traditional_http`、`ai_chat` 或 `ai_stream`。                                                                         |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型；传统 HTTP 流量中为空字符串。 |
| response_source    | 响应来源：`apisix` 表示由 APISIX 生成，`nginx` 表示 NGINX 代理错误，`upstream` 表示来自上游服务的响应。                              |

### `apisix_stream_active_connections` 的标签

接受会话时，该 gauge 会递增；会话结束时递减，因此无需等到会话结束即可反映实时并发量。

| 名称 | 描述 |
| --- | --- |
| listen_addr | 客户端连接的监听地址，例如 `0.0.0.0:9100`。 |

### `apisix_stream_status` 的标签

上游连接建立后发生的故障在 NGINX Stream `$status` 中都可能显示为 200，因此仅凭该值无法区分超时、连接重置和正常关闭。此指标利用运行时记录的终止原因，将会话归类到 NGINX Stream 使用的状态代码中，不引入自定义状态代码。

| 名称 | 描述 |
| --- | --- |
| code | 会话结束方式：`200` 表示正常关闭；`400` 表示客户端重置或预读数据无效等客户端问题；`403` 表示被访问规则拒绝；`500` 表示内部错误；`502` 表示连接失败、重置或空闲超时等上游或传输问题；`503` 表示被连接数限制拒绝。 |
| listen_addr | 客户端连接的监听地址，例如 `0.0.0.0:9100`。 |
| node | 使用的上游节点地址；未选择节点时为空。 |

UDP 没有关闭、FIN 或重置信号，因此只会出现其中一部分状态代码。

### `apisix_stream_bandwidth` 的标签

字节计数在连接保持打开时持续累积，因此可观察长连接的实时流量。该指标只统计 Stream 流量，不包含 HTTP 子系统流量。

| 名称 | 描述 |
| --- | --- |
| listen_addr | 客户端连接的监听地址，例如 `0.0.0.0:9100`。 |
| side | 字节经过的连接侧：`downstream` 表示 APISIX 与客户端之间，`upstream` 表示 APISIX 与上游之间。 |
| type | 相对 APISIX 的方向，与 `apisix_bandwidth` 一致：`ingress` 表示 APISIX 接收的字节，`egress` 表示 APISIX 发送的字节。 |

在普通转发中，`downstream`/`ingress` 通常对应 `upstream`/`egress`，`upstream`/`ingress` 通常对应 `downstream`/`egress`；持续不一致可能表示某一侧停止读取。

### `apisix_bandwidth` 的标签

以下标签用于区分 `apisix_bandwidth` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| type   | 流量类型，`egress` 或 `ingress`。                                                                                     |
| route  | 请求对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| service | 请求对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 上游节点的 IP 地址。                                                                                                   |
| request_type       | 请求类别：`traditional_http`、`ai_chat` 或 `ai_stream`。                                                                         |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型；传统 HTTP 流量中为空字符串。 |

### `apisix_llm_latency` 的标签

`type` 标签用于区分延迟类型，与 `apisix_http_latency` 类似：

- `total`：完整的响应延迟，`ai_chat` 和 `ai_stream` 请求都会记录。
- `ttft`：首个 token 到达时间，仅 `ai_stream` 请求记录（非流式响应没有"首个 token"这一时刻）。

对于按请求记录的 LLM 指标，名为 `route_id` 和 `service_id` 的标签遵循 `prefer_name`：默认保存 ID，`prefer_name` 为 `true` 时保存名称。`apisix_llm_active_connections` 不同，它会分别导出名称和 ID 标签。

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| type          | 延迟类型：`total` 或 `ttft`。                                                                                                    |
| route_id      | 请求对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。                        |
| service_id    | 指标对应的服务 ID；`prefer_name` 为 `true` 时保存服务名称。如果匹配路由未引用服务，则默认为空字符串。              |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_llm_active_connections` 的标签

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route      | 匹配路由的名称。如果路由没有名称或请求未匹配任何路由，则默认为空字符串。                                          |
| route_id   | 匹配路由的 ID。如果请求未匹配任何路由，则默认为空字符串。                                                        |
| matched_uri | 匹配请求的路由 URI。如果请求不匹配任何路由，则默认为空字符串。                                                       |
| matched_host | 匹配请求的路由主机。如果请求不匹配任何路由，或路由未配置主机，则默认为空字符串。                                     |
| service    | 匹配路由引用的服务名称。如果路由未引用服务，则默认为空字符串。                                                      |
| service_id | 匹配路由引用的服务 ID。如果路由未引用服务，则默认为空字符串。                                                        |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_llm_completion_tokens` 的标签

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route_id      | 指标对应的路由 ID；`prefer_name` 为 `true` 时保存路由名称。如果请求未匹配任何路由，则默认为空字符串。              |
| service_id    | 指标对应的服务 ID；`prefer_name` 为 `true` 时保存服务名称。如果匹配路由未引用服务，则默认为空字符串。              |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_llm_prompt_tokens` 的标签

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route_id      | 指标对应的路由 ID；`prefer_name` 为 `true` 时保存路由名称。如果请求未匹配任何路由，则默认为空字符串。              |
| service_id    | 指标对应的服务 ID；`prefer_name` 为 `true` 时保存服务名称。如果匹配路由未引用服务，则默认为空字符串。              |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_llm_prompt_tokens_dist` 的标签

`apisix_llm_prompt_tokens_dist` 是每次请求消耗的 prompt token 数的直方图，作为 `apisix_llm_prompt_tokens` 计数器的补充，提供分布信息以便计算分位数（如 p95 prompt 大小）。

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route_id      | 指标对应的路由 ID；`prefer_name` 为 `true` 时保存路由名称。如果请求未匹配任何路由，则默认为空字符串。              |
| service_id    | 指标对应的服务 ID；`prefer_name` 为 `true` 时保存服务名称。如果匹配路由未引用服务，则默认为空字符串。              |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_llm_completion_tokens_dist` 的标签

`apisix_llm_completion_tokens_dist` 是每次请求生成的 completion token 数的直方图，作为 `apisix_llm_completion_tokens` 计数器的补充，提供分布信息。

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| route_id      | 指标对应的路由 ID；`prefer_name` 为 `true` 时保存路由名称。如果请求未匹配任何路由，则默认为空字符串。              |
| service_id    | 指标对应的服务 ID；`prefer_name` 为 `true` 时保存服务名称。如果匹配路由未引用服务，则默认为空字符串。              |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | 所选 AI 上游的标识，通常是 `ai-proxy` 或 `ai-proxy-multi` 上报的 LLM 实例名称。                                |
| request_type       | 请求类别：`ai_chat` 或 `ai_stream`。                                                                                             |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。 |

### `apisix_ai_cache_*` 系列指标的标签

[`ai-cache`](./ai-cache.md) 插件导出以下四个指标：

- `apisix_ai_cache_hits_total`：统计由缓存命中并直接返回的请求数，按命中的缓存层区分。
- `apisix_ai_cache_misses_total`：统计经过插件查询但未命中缓存的请求数。
- `apisix_ai_cache_bypasses_total`：统计完全绕过缓存查询的请求数。
- `apisix_ai_cache_embedding_latency`：语义层发起的 embedding 调用延迟（毫秒）的直方图，围绕 embedding 服务的完整往返计时，成功与失败的调用均会记录。

它们共享以下标签：

| 名称 | 描述 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| layer      | 仅存在于 `apisix_ai_cache_hits_total`。命中的缓存层：`exact` 或 `semantic`。                                                                                 |
| route      | 指标对应的路由名称。如果路由未配置名称或请求不匹配任何路由，则默认为空字符串。                         |
| route_id      | 指标对应的路由 ID。如果请求不匹配任何路由，则默认为空字符串。                         |
| service    | 匹配路由所属的服务名称。如果匹配的路由不属于任何服务，则默认为空字符串。 |
| service_id    | 匹配路由所属的服务 ID。如果匹配的路由不属于任何服务，则默认为空字符串。 |
| consumer   | 与请求关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                       |
| node       | `ai-proxy` 或 `ai-proxy-multi` 插件选中的 LLM 实例名称，例如 `ai-proxy-openai`。这些插件上报的是实例名称而非上游 IP 地址，缓存命中与未命中时均是如此。                                                                                          |
| request_type       | AI 请求类别：`ai_chat` 或 `ai_stream`。                                                                                          |
| request_llm_model       | 客户端请求的模型名称。                                                                                          |
| llm_model       | 上游 AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型。缓存命中的请求不会到达 LLM，因此该标签为空字符串。 |

### `apisix_http_latency` 的标签

以下标签用于区分 `apisix_http_latency` 指标。

| 名称   | 描述                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------- |
| type   | 延迟类型。有关详细信息，请参见 [延迟类型](#延迟类型)。                                                            |
| route  | 延迟对应的路由 ID，当 `prefer_name` 为 `false`（默认）时，使用路由 ID，当 `prefer_name` 为 `true` 时，使用路由名称。如果请求不匹配任何路由，则默认为空字符串。 |
| service | 延迟对应的服务 ID，当 `prefer_name` 为 `false`（默认）时，使用服务 ID，当 `prefer_name` 为 `true` 时，使用服务名称。如果匹配的路由不属于任何服务，则默认为路由上配置的主机值。 |
| consumer | 与延迟关联的消费者名称。如果请求没有与之关联的消费者，则默认为空字符串。                                             |
| node   | 与延迟关联的上游节点的 IP 地址。                                                                                     |
| request_type       | 请求类别：`traditional_http`、`ai_chat` 或 `ai_stream`。                                                                         |
| request_llm_model  | 客户端请求的模型名称。                                                                                                           |
| llm_model          | AI 请求实际使用的目标模型。优先使用 AI 实例中配置的模型，否则使用客户端请求的模型；传统 HTTP 流量中为空字符串。 |

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

默认的 Prometheus 指标端点和其他与 Prometheus 相关的配置可以在 [静态配置](#静态配置) 中找到。如果你希望自定义这些配置，更新 `config.yaml` 并重新加载 APISIX。

如果你在容器化环境中部署 APISIX，并希望外部访问 Prometheus 指标端点，请按如下方式更新配置文件并重新加载 APISIX：

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

你应该看到类似以下的输出：

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

:::caution

如果收集了大量指标，插件可能会占用大量 CPU 资源进行指标计算，从而对常规请求的处理产生负面影响。

为了解决这个问题，APISIX 使用[特权代理](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent)，将指标收集和计算卸载到一个单独的进程，并通过共享缓存供 HTTP 处理器返回。如果你使用配置文件中配置的指标端点（如[上文](#获取-apisix-指标)所示），此优化将自动生效。如果你使用 `public-api` 插件公开指标端点，仍然会使用这一缓存/卸载机制；不过，请求会额外经过 API 路由处理链，并且指标会暴露在公共监听端口上。

:::

在配置文件中禁用 Prometheus 导出服务器，并重新加载 APISIX 以使更改生效：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

接下来，使用 [`public-api`](./public-api.md) 插件创建一个路由，并为 APISIX 指标公开一个公共 API 端点：

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

你应该看到类似以下的输出：

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

你应该看到类似以下的输出：

```text
# HELP apisix_upstream_status 上游健康检查的状态
# TYPE apisix_upstream_status gauge
apisix_upstream_status{name="/apisix/routes/1",ip="54.237.103.220",port="80"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="20001"} 0
```

这显示上游节点 `httpbin.org:80` 是健康的，而上游节点 `127.0.0.1:20001` 是不健康的。

### 为指标添加额外标签

以下示例演示如何为指标添加额外标签，并在标签值中使用 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。

`apisix_http_status`、`apisix_http_latency`、`apisix_bandwidth`、上文列出的所有 `apisix_llm_*` 指标，以及四个 `apisix_ai_cache_*` 指标均支持额外标签。

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

请注意，如果你在标签值中定义了一个变量，但它与任何现有的 [APISIX 变量](https://apisix.apache.org/zh/docs/apisix/apisix-variable/) 和 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) 不对应，则标签值将默认为空字符串。

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

你应该看到 `HTTP/1.1 200 OK` 的响应。

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

你应该看到类似以下的输出：

```text
# HELP apisix_http_status APISIX 中每个服务的 HTTP 状态代码
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="1",matched_uri="/get",matched_host="",service="",consumer="",node="54.237.103.220",upstream_addr="54.237.103.220:80",route_name="extra-label"} 1
```

### 通过禁用标签降低指标基数

以下示例演示如何通过[插件元数据（Plugin Metadata）](../terminology/plugin-metadata.md)将选定内置标签的值折叠为空字符串 `""`，从而降低指标基数。这在 Kubernetes 弹性伸缩等动态环境中尤其有用：此时上游节点 IP（`node` 标签）频繁变化，否则会很快撑爆 `prometheus-metrics` 共享字典。

将标签值折叠后，标签仍保留在指标 schema 中，因此现有的仪表盘、`absent()` 告警和 recording rule 都不受影响。定义指标本身含义的结构性标签（`http_status` 的 `code`、`http_latency`、`bandwidth` 与 `llm_latency` 的 `type`）不可被禁用。

创建一个启用 `prometheus` 插件的路由：

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
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

配置插件元数据，将 `apisix_http_status` 的 `node` 和 `consumer` 标签、以及 `apisix_http_latency` 的 `node` 标签的值折叠：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/prometheus" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "disabled_labels": {
      "http_status": ["node", "consumer"],
      "http_latency": ["node"]
    }
  }'
```

向路由发送请求以进行验证：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该看到 `HTTP/1.1 200 OK` 的响应。

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

你应该看到 `apisix_http_status` 中的 `node` 和 `consumer` 被折叠为空字符串，而未列出的指标（如 `apisix_bandwidth`）仍保留其所有标签值：

```text
# HELP apisix_http_status APISIX 中每个服务的 HTTP 状态代码
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="prometheus-route",matched_uri="/get",matched_host="",service="",consumer="",node="",request_type="traditional_http",request_llm_model="",llm_model="",response_source="upstream"} 1
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
    "id": "prometheus-route",
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

你应该看到 `HTTP/1.1 200 OK` 的响应。

向 APISIX Prometheus 指标端点发送请求：

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

你应该看到类似以下的输出：

```text
# HELP apisix_stream_connection_total APISIX 中每个 Stream Route 处理的总连接数
# TYPE apisix_stream_connection_total counter
apisix_stream_connection_total{route="1"} 1
```
