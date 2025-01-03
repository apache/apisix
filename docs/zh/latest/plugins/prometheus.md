---
title: prometheus
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Prometheus
description:  本文将介绍 API 网关 Apache APISIX 如何通过 prometheus 插件将 metrics 上报到开源的监控软件 Prometheus。
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

`prometheus` 插件以 [Prometheus 文档](https://prometheus.io/docs/instrumenting/exposition_formats/#exposition-formats)规定的格式上报指标到 Prometheus 中。

## 属性

| 名称         | 类型     | 必选项 | 默认值 |  描述                                                  |
| ------------ | --------| ------ | ------ | ----------------------------------------------------- |
| prefer_name  | boolean | 否     | false  | 当设置为 `true` 时，将使用路由或服务的 `name` 标识请求所命中的路由或服务，否则使用其 `id`。 |

:::note

多个路由或服务可以设置为相同的名称，所以当设置 `prefer_name` 为 `true` 时，请规范路由和服务的命名，否则容易引起误解。

:::

### 如何修改暴露指标的 `export_uri`

你可以在配置文件 `./conf/config.yaml` 的 `plugin_attr` 列表下修改默认的 URI。

| 名称       | 类型    | 默认值                       | 描述                         |
| ---------- | ------ | ---------------------------- | --------------------------- |
| export_uri | string | "/apisix/prometheus/metrics" | 暴露 Prometheus 指标的 URI。 |

配置示例如下：

```yaml title="./conf/config.yaml"
plugin_attr:
  prometheus:
    export_uri: /apisix/metrics
```

### 如何修改延迟指标中的 `default_buckets`

`DEFAULT_BUCKETS` 是 `http_latency` 指标中 bucket 数组的默认值。

你可以通过修改配置文件中的 `default_buckets` 来重新指定 `DEFAULT_BUCKETS`

配置示例如下：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    default_buckets:
      - 15
      - 55
      - 105
      - 205
      - 505
```

### 如何修改指标的 `expire`

`expire` 用于设置 `apisix_http_status`、`apisix_bandwidth` 和 `apisix_http_latency` 指标的过期时间（以秒为单位）。当设置为 0 时，指标不会过期。

配置示例如下：

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    expire: 86400
```

## API

`prometheus` 插件会增加 `/apisix/prometheus/metrics` 接口或者你自定义的 URI 来暴露其指标信息。

这些指标由独立的 Prometheus 服务器地址公开。默认情况下，地址为 `127.0.0.1:9091`。你可以在配置文件（`./conf/config.yaml`）中修改，示例如下：

```yaml title="./conf/config.yaml"
plugin_attr:
  prometheus:
    export_addr:
      ip: ${{INTRANET_IP}}
      port: 9092
```

假设环境变量 `INTRANET_IP` 是 `172.1.1.1`，那么 APISIX 将会在 `172.1.1.1:9092` 上暴露指标。

如果你仍然想要让指标暴露在数据面的端口（默认：`9080`）上，可参考如下配置：

```yaml title="./conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

你可以使用 [public-api](../../../en/latest/plugins/public-api.md) 插件来暴露该 URI。

:::info IMPORTANT

如果 Prometheus 插件收集的指标数量过多，在通过 URI 获取指标时，会占用 CPU 资源来计算指标数据，可能会影响 APISIX 处理正常请求。为解决此问题，APISIX 在 [privileged agent](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) 中暴露 URI 并且计算指标。
如果使用 public-api 插件暴露该 URI，那么 APISIX 将在普通的 worker 进程中计算指标数据，这仍可能会影响 APISIX 处理正常请求。

该特性要求 APISIX  运行在 [APISIX-Runtime](../FAQ.md#如何构建-apisix-runtime-环境) 上。

:::

## 启用插件

`prometheus` 插件可以使用空表 `{}` 开启。

你可以通过如下命令在指定路由上启用 `prometheus` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "prometheus":{}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

<!-- 你可以使用 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 通过 web 界面来完成上面的操作。

先增加一个 Route：

![create a route](../../../assets/images/plugin/prometheus-1.png)

然后在 route 页面中添加 prometheus 插件：

![enable prometheus plugin](../../../assets/images/plugin/prometheus-2.png) -->

## 提取指标

你可以从指定的 URL（默认：`/apisix/prometheus/metrics`）中提取指标数据：

```
curl -i http://127.0.0.1:9091/apisix/prometheus/metrics
```

你可以将该 URI 地址添加到 Prometheus 中来提取指标数据，配置示例如下：

```yaml title="./prometheus.yml"
scrape_configs:
  - job_name: "apisix"
    scrape_interval: 15s # 该值会跟 Prometheus QL 中 rate 函数的时间范围有关系，rate 函数中的时间范围应该至少两倍于该值。
    metrics_path: "/apisix/prometheus/metrics"
    static_configs:
      - targets: ["127.0.0.1:9091"]
```

现在你可以在 Prometheus 控制台中检查状态：

![checking status on prometheus dashboard](../../../assets/images/plugin/prometheus01.png)

![prometheus apisix in-depth metric view](../../../assets/images/plugin/prometheus02.png)

## 使用 Grafana 绘制指标

`prometheus` 插件导出的指标可以在 Grafana 进行图形化绘制显示。

如果需要进行设置，请下载 [APISIX's Grafana dashboard 元数据](https://github.com/apache/apisix/blob/master/docs/assets/other/json/apisix-grafana-dashboard.json) 并导入到 Grafana 中。

你可以到 [Grafana 官方](https://grafana.com/grafana/dashboards/11719) 下载 `Grafana` 元数据。

![Grafana chart-1](../../../assets/images/plugin/grafana-1.png)

![Grafana chart-2](../../../assets/images/plugin/grafana-2.png)

![Grafana chart-3](../../../assets/images/plugin/grafana-3.png)

![Grafana chart-4](../../../assets/images/plugin/grafana-4.png)

## 可用的 HTTP 指标

`prometheus` 插件可以导出以下指标：

- Status codes: 上游服务返回的 HTTP 状态码，可以统计到每个服务或所有服务的响应状态码的次数总和。属性如下所示：

    | 名称          |    描述                                                                       |
    | -------------| ----------------------------------------------------------------------------- |
    | code         | 上游服务返回的 HTTP 状态码。                                                    |
    | route        | 与请求匹配的路由的 `route_id`，如果未匹配，则默认为空字符串。                     |
    | matched_uri  | 与请求匹配的路由的 `uri`，如果未匹配，则默认为空字符串。                           |
    | matched_host | 与请求匹配的路由的 `host`，如果未匹配，则默认为空字符串。                          |
    | service      | 与请求匹配的路由的 `service_id`。当路由缺少 `service_id` 时，则默认为 `$host`。    |
    | consumer     | 与请求匹配的消费者的 `consumer_name`。如果未匹配，则默认为空字符串。                |
    | node         | 上游节点 IP 地址。                                                               |

- Bandwidth: 经过 APISIX 的总带宽（出口带宽和入口带宽），可以统计到每个服务的带宽总和。属性如下所示：

    | 名称          |    描述        |
    | -------------| ------------- |
    | type         | 带宽的类型 (`ingress` 或 `egress`)。 |
    | route        | 与请求匹配的路由的 `route_id`，如果未匹配，则默认为空字符串。 |
    | service      | 与请求匹配的路由的 `service_id`。当路由缺少 `service_id` 时，则默认为 `$host`。 |
    | consumer     | 与请求匹配的消费者的 `consumer_name`。如果未匹配，则默认为空字符串。 |
    | node         | 消费者节点 IP 地址。 |

- etcd reachability: APISIX 连接 etcd 的可用性，用 0 和 1 来表示，`1` 表示可用，`0` 表示不可用。
- Connections: 各种的 NGINX 连接指标，如 `active`（正处理的活动连接数），`reading`（NGINX 读取到客户端的 Header 信息数），writing（NGINX 返回给客户端的 Header 信息数），已建立的连接数。
- Batch process entries: 批处理未发送数据计数器，当你使用了批处理发送插件，比如：[syslog](./syslog.md), [http-logger](./http-logger.md), [tcp-logger](./tcp-logger.md), [udp-logger](./udp-logger.md), and [zipkin](./zipkin.md)，那么你将会在此指标中看到批处理当前尚未发送的数据的数量。
- Latency: 每个服务的请求用时和 APISIX 处理耗时的直方图。属性如下所示：

    | 名称          |    描述                                                                                 |
    | -------------| --------------------------------------------------------------------------------------- |
    | type         | 该值可以是 `apisix`、`upstream` 和 `request`，分别表示耗时的来源是 APISIX、上游以及两者总和。 |
    | route        | 与请求匹配的路由的 `route_id`，如果未匹配，则默认为空字符串。 |
    | service      | 与请求匹配的路由 的 `service_id`。当路由缺少 `service_id` 时，则默认为 `$host`。             |
    | consumer     | 与请求匹配的消费者的 `consumer_name`。未匹配，则默认为空字符串。                             |
    | node         | 上游节点的 IP 地址。                                                                      |

- Info: 当前 APISIX 节点信息。
- Shared dict: APISIX 中所有共享内存的容量以及剩余可用空间。
- `apisix_upstream_status`: 上游健康检查的节点状态，`1` 表示健康，`0` 表示不健康。属性如下所示：

  | 名称         | 描述                                                                                                                   |
  |--------------|-------------------------------------------------------------------------------------------------------------------------------|
  | name         | 上游所依附的资源 ID，例如 `/apisix/routes/1`, `/apisix/upstreams/1`.                                                                            |
  | ip        | 上游节点的 IP 地址。                          |
  | port  | 上游节点的端口号。                               |

以下是 APISIX 的原始的指标数据集：

```shell
curl http://127.0.0.1:9091/apisix/prometheus/metrics
```

```shell
# HELP apisix_bandwidth Total bandwidth in bytes consumed per service in Apisix
# TYPE apisix_bandwidth counter
apisix_bandwidth{type="egress",route="",service="",consumer="",node=""} 8417
apisix_bandwidth{type="egress",route="1",service="",consumer="",node="127.0.0.1"} 1420
apisix_bandwidth{type="egress",route="2",service="",consumer="",node="127.0.0.1"} 1420
apisix_bandwidth{type="ingress",route="",service="",consumer="",node=""} 189
apisix_bandwidth{type="ingress",route="1",service="",consumer="",node="127.0.0.1"} 332
apisix_bandwidth{type="ingress",route="2",service="",consumer="",node="127.0.0.1"} 332
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 0
apisix_etcd_modify_indexes{key="max_modify_index"} 222
apisix_etcd_modify_indexes{key="prev_index"} 35
apisix_etcd_modify_indexes{key="protos"} 0
apisix_etcd_modify_indexes{key="routes"} 222
apisix_etcd_modify_indexes{key="services"} 0
apisix_etcd_modify_indexes{key="ssls"} 0
apisix_etcd_modify_indexes{key="stream_routes"} 0
apisix_etcd_modify_indexes{key="upstreams"} 0
apisix_etcd_modify_indexes{key="x_etcd_index"} 223
# HELP apisix_batch_process_entries batch process remaining entries
# TYPE apisix_batch_process_entries gauge
apisix_batch_process_entries{name="http-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="sls-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="tcp-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="udp-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="sys-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="zipkin_report",route_id="9",server_addr="127.0.0.1"} 1
# HELP apisix_etcd_reachable Config server etcd reachable from Apisix, 0 is unreachable
# TYPE apisix_etcd_reachable gauge
apisix_etcd_reachable 1
# HELP apisix_http_status HTTP status codes per service in Apisix
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="1",matched_uri="/hello",matched_host="",service="",consumer="",node="127.0.0.1"} 4
apisix_http_status{code="200",route="2",matched_uri="/world",matched_host="",service="",consumer="",node="127.0.0.1"} 4
apisix_http_status{code="404",route="",matched_uri="",matched_host="",service="",consumer="",node=""} 1
# HELP apisix_http_requests_total The total number of client requests
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 1191780
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 11994
apisix_nginx_http_current_connections{state="active"} 2
apisix_nginx_http_current_connections{state="handled"} 11994
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 1
apisix_nginx_http_current_connections{state="writing"} 1
# HELP apisix_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE apisix_nginx_metric_errors_total counter
apisix_nginx_metric_errors_total 0
# HELP apisix_http_latency HTTP request latency in milliseconds per service in APISIX
# TYPE apisix_http_latency histogram
apisix_http_latency_bucket{type="apisix",route="1",service="",consumer="",node="127.0.0.1",le="1"} 1
apisix_http_latency_bucket{type="apisix",route="1",service="",consumer="",node="127.0.0.1",le="2"} 1
apisix_http_latency_bucket{type="request",route="1",service="",consumer="",node="127.0.0.1",le="1"} 1
apisix_http_latency_bucket{type="request",route="1",service="",consumer="",node="127.0.0.1",le="2"} 1
apisix_http_latency_bucket{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="1"} 1
apisix_http_latency_bucket{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="2"} 1
...
# HELP apisix_node_info Info of APISIX node
# TYPE apisix_node_info gauge
apisix_node_info{hostname="APISIX"} 1
# HELP apisix_shared_dict_capacity_bytes The capacity of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_capacity_bytes gauge
apisix_shared_dict_capacity_bytes{name="access-tokens"} 1048576
apisix_shared_dict_capacity_bytes{name="balancer-ewma"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-last-touched-at"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-locks"} 10485760
apisix_shared_dict_capacity_bytes{name="discovery"} 1048576
apisix_shared_dict_capacity_bytes{name="etcd-cluster-health-check"} 10485760
...
# HELP apisix_shared_dict_free_space_bytes The free space of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_free_space_bytes gauge
apisix_shared_dict_free_space_bytes{name="access-tokens"} 1032192
apisix_shared_dict_free_space_bytes{name="balancer-ewma"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-last-touched-at"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-locks"} 10412032
apisix_shared_dict_free_space_bytes{name="discovery"} 1032192
apisix_shared_dict_free_space_bytes{name="etcd-cluster-health-check"} 10412032
...
# HELP apisix_upstream_status Upstream status from health check
# TYPE apisix_upstream_status gauge
apisix_upstream_status{name="/apisix/routes/1",ip="100.24.156.8",port="80"} 0
apisix_upstream_status{name="/apisix/routes/1",ip="52.86.68.46",port="80"} 1
```

## 删除插件

当你需要禁用 `prometheus` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## 如何启用 TCP/UDP 指标

:::info IMPORTANT

该功能要求 APISIX 运行在 [APISIX-Runtime](../FAQ.md#如何构建-APISIX-Runtime-环境？) 上。

:::

我们也可以通过 `prometheus` 插件采集 TCP/UDP 指标。

首先，确保 `prometheus` 插件已经在你的配置文件（`./conf/config.yaml`）中启用：

```yaml title="conf/config.yaml"
stream_plugins:
  - ...
  - prometheus
```

接着你需要在 stream 路由中配置该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "prometheus":{}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## 可用的 TCP/UDP 指标

以下是将 APISIX 作为 L4 代理时可用的指标：

* Stream Connections: 路由级别的已处理连接数。具有的维度：

    | 名称          |    描述                 |
    | ------------- | ---------------------- |
    | route         | 匹配的 stream 路由 ID。 |
* Connections: 各种的 NGINX 连接指标，如 `active`，`reading`，`writing` 等已建立的连接数。
* Info: 当前 APISIX 节点信息。

以下是 APISIX 指标的示例：

```shell
curl http://127.0.0.1:9091/apisix/prometheus/metrics
```

```
...
# HELP apisix_node_info Info of APISIX node
# TYPE apisix_node_info gauge
apisix_node_info{hostname="desktop-2022q8f-wsl"} 1
# HELP apisix_stream_connection_total Total number of connections handled per stream route in APISIX
# TYPE apisix_stream_connection_total counter
apisix_stream_connection_total{route="1"} 1
```
