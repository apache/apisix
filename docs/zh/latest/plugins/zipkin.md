---
title: zipkin
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Zipkin
description: Zipkin 是一个开源的分布式链路追踪系统。`zipkin` 插件为 APISIX 提供了追踪功能，并根据 Zipkin API 规范将追踪数据上报给 Zipkin。
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
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
  <link rel="canonical" href="https://docs.api7.ai/hub/zipkin" />
</head>

## 描述

[Zipkin](https://github.com/openzipkin/zipkin) 是一个开源的分布式链路追踪系统。`zipkin` 插件为 APISIX 提供了追踪功能，并根据 [Zipkin API 规范](https://zipkin.io/pages/instrumenting.html) 将追踪数据上报给 Zipkin。

该插件还支持将追踪数据发送到其他兼容的收集器，例如 [Jaeger](https://www.jaegertracing.io/docs/1.51/getting-started/#migrating-from-zipkin) 和 [Apache SkyWalking](https://skywalking.apache.org/docs/main/latest/en/setup/backend/zipkin-trace/#zipkin-receiver)，这两者都支持 Zipkin [v1](https://zipkin.io/zipkin-api/zipkin-api.yaml) 和 [v2](https://zipkin.io/zipkin-api/zipkin2-api.yaml) API。

## 静态配置

默认情况下，`zipkin` 插件的 NGINX 变量配置在 [默认配置](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua) 中设置为 `false`：

要修改此值，请将更新后的配置添加到 `config.yaml` 中。例如：

```yaml
plugin_attr:
  zipkin:
    set_ngx_var: true
```

重新加载 APISIX 以使更改生效。

## 属性

查看配置文件以获取所有插件可用的配置选项。

| 名称          | 类型     | 是否必需    | 默认值        | 有效值      |      描述     |
|--------------|---------|----------|----------------|-------------|------------------|
| endpoint     | string   | 是       |                |            | 要 POST 的 Zipkin span 端点，例如 `http://127.0.0.1:9411/api/v2/spans`。 |
|sample_ratio| number    | 是       |                | [0.00001, 1] | 请求采样频率。设置为 `1` 表示对每个请求进行采样。    |
|service_name| string  | 否       | "APISIX"       |              | 在 Zipkin 中显示的服务名称。   |
|server_addr | string  | 否       | `$server_addr` 的值 | IPv4 地址 | Zipkin 报告器的 IPv4 地址。例如，可以将其设置为你的外部 IP 地址。 |
|span_version| integer    | 否       | `2`            | [1, 2]       | span 类型的版本。    |

## 示例

以下示例展示了使用 `zipkin` 插件的不同用例。

### 将追踪数据发送到 Zipkin

以下示例演示了如何追踪对路由的请求，并将追踪数据发送到使用 [Zipkin API v2](https://zipkin.io/zipkin-api/zipkin2-api.yaml) 的 Zipkin。还将介绍 span 版本 2 和 版本 1 之间的区别。

在 Docker 中启动一个 Zipkin 实例：

```shell
docker run -d --name zipkin -p 9411:9411 openzipkin/zipkin
```

创建一条路由，开启 `zipkin` 插件，并使用其默认的 `span_version`，即 `2`。同时请根据需要调整 Zipkin HTTP 端点的 IP 地址，将采样比率配置为 `1` 以追踪每个请求。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes"  -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "zipkin-tracing-route",
    "uri": "/anything",
    "plugins": {
      "zipkin": {
        "endpoint": "http://127.0.0.1:9411/api/v2/spans",
        "sample_ratio": 1,
        "span_version": 2
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything"
```

你应该收到一个类似于以下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.64.1",
    "X-Amzn-Trace-Id": "Root=1-65af2926-497590027bcdb09e34752b78",
    "X-B3-Parentspanid": "347dddedf73ec176",
    "X-B3-Sampled": "1",
    "X-B3-Spanid": "429afa01d0b0067c",
    "X-B3-Traceid": "aea58f4b490766eccb08275acd52a13a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  ...
}
```

导航到 Zipkin Web UI [http://127.0.0.1:9411/zipkin](http://127.0.0.1:9411/zipkin) 并点击 __Run Query__，你应该看到一个与请求对应的 trace：

![来自请求的追踪](https://static.api7.ai/uploads/2024/01/23/MaXhacYO_zipkin-run-query.png)

点击 __Show__ 查看更多 trace 细节：

![v2 trace span](https://static.api7.ai/uploads/2024/01/23/3SmfFq9f_trace-details.png)

请注意，使用 span 版本 2 时，每个被 trace 的请求会创建以下 span：

```text
request
├── proxy
└── response
```

其中 `proxy` 表示从请求开始到 `header_filter` 开始的时间，而 `response` 表示从 `header_filter` 开始到 `log` 开始的时间。

现在，更新路由上的插件以使用 span 版本 1：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/zipkin-tracing-route"  -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "zipkin": {
        "span_version": 1
      }
    }
  }'
```

向路由发送另一个请求：

```shell
curl "http://127.0.0.1:9080/anything"
```

在 Zipkin Web UI 中，你应该看到一个具有以下细节的新 trace：

![v1 trace span](https://static.api7.ai/uploads/2024/01/23/OPw2sTPa_v1-trace-spans.png)

请注意，使用较旧的 span 版本 1 时，每个被追踪的请求会创建以下 span：

```text
request
├── rewrite
├── access
└── proxy
    └── body_filter
```

### 将追踪数据发送到 Jaeger

以下示例演示了如何追踪对路由的请求并将追踪数据发送到 Jaeger。

在 Docker 中启动一个 Jaeger 实例：

```shell
docker run -d --name jaeger \
  -e COLLECTOR_ZIPKIN_HOST_PORT=9411 \
  -p 16686:16686 \
  -p 9411:9411 \
  jaegertracing/all-in-one
```

创建一条路由并开启 `zipkin` 插件。请根据需要调整 Zipkin HTTP 端点的 IP 地址，并将采样比率配置为 `1` 以追踪每个请求。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "zipkin-tracing-route",
    "uri": "/anything",
    "plugins": {
      "zipkin": {
        "endpoint": "http://127.0.0.1:9411/api/v2/spans",
        "sample_ratio": 1
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything"
```

你应该收到一个 `HTTP/1.1 200 OK` 响应。

导航到 Jaeger Web UI [http://127.0.0.1:16686](http://127.0.0.1:16686)，选择 APISIX 作为服务，并点击 __Find Traces__，您应该看到一个与请求对应的 trace：

![jaeger trace](https://static.api7.ai/uploads/2024/01/23/X6QdLN3l_jaeger.png)

同样地，一旦点击进入一个追踪，你应该会找到更多 span 细节：

![jaeger 细节](https://static.api7.ai/uploads/2024/01/23/iP9fXI2A_jaeger-details.png)

### 在日志中使用追踪变量

以下示例演示了如何配置 `zipkin` 插件以设置以下内置变量，这些变量可以在日志插件或访问日志中使用：

- `zipkin_context_traceparent`: [W3C trace context](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format)
- `zipkin_trace_id`: 当前 span 的 trace_id
- `zipkin_span_id`: 当前 span 的 span_id

按照以下方式更新配置文件。你可以自定义访问日志格式以使用 `zipkin` 插件变量，并在 `set_ngx_var` 字段中设置 `zipkin` 变量。

```yaml title="conf/config.yaml"
nginx_config:
  http:
    enable_access_log: true
    access_log_format: '{"time": "$time_iso8601","zipkin_context_traceparent": "$zipkin_context_traceparent","zipkin_trace_id": "$zipkin_trace_id","zipkin_span_id": "$zipkin_span_id","remote_addr": "$remote_addr"}'
    access_log_format_escape: json
plugin_attr:
  zipkin:
    set_ngx_var: true
```

重新加载 APISIX 以使配置更改生效。

当生成请求时，你应该看到类似的访问日志：

```text
{"time": "23/Jan/2024:06:28:00 +0000","zipkin_context_traceparent": "00-61bce33055c56f5b9bec75227befd142-13ff3c7370b29925-01","zipkin_trace_id": "61bce33055c56f5b9bec75227befd142","zipkin_span_id": "13ff3c7370b29925","remote_addr": "172.28.0.1"}
```
