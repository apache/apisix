---
title: opentelemetry
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - OpenTelemetry
description: opentelemetry 插件可用于根据 OpenTelemetry 协议规范上报 Traces 数据，该插件仅支持二进制编码的 OLTP over HTTP。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/opentelemetry" />
</head>

## 描述

`opentelemetry` 插件可用于根据 [OpenTelemetry Specification](https://opentelemetry.io/docs/reference/specification/) 协议规范上报 Traces 数据。该插件仅支持二进制编码的 OLTP over HTTP，即请求类型为 `application/x-protobuf` 的数据上报。

## 配置

默认情况下，服务名称、租户 ID、collector 和 batch span processor 的配置已预配置在[默认配置](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua)中。

您可以通过端点 `apisix/admin/plugin_metadata/opentelemetry` 更改插件的配置，例如：

:::note
您可以从“config.yaml”获取“admin_key”,并使用以下命令保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/opentelemetry -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "trace_id_source": "x-request-id",
    "resource": {
      "service.name": "APISIX"
    },
    "collector": {
      "address": "127.0.0.1:4318",
      "request_timeout": 3,
      "request_headers": {
        "Authorization": "token"
      }
    },
    "batch_span_processor": {
      "drop_on_queue_full": false,
      "max_queue_size": 1024,
      "batch_timeout": 2,
      "inactive_timeout": 1,
      "max_export_batch_size": 16
    },
    "set_ngx_var": false
}'
```

## 属性

| 名称                                  | 类型           | 必选项    | 默认值        | 有效值        | 描述 |
|---------------------------------------|---------------|----------|--------------|--------------|-------------|
| sampler                               | object        | 否       | -            | -            | 采样策略。    |
| sampler.name                          | string        | 否       | `always_off` | ["always_on", "always_off", "trace_id_ratio", "parent_base"]  | 采样策略。<br />`always_on`：全采样；`always_off`：不采样；`trace_id_ratio`：基于 trace id 的百分比采样；`parent_base`：如果存在 tracing 上游，则使用上游的采样决定，否则使用配置的采样策略决策。|
| sampler.options                       | object        | 否       | -            | -            | 采样策略参数。 |
| sampler.options.fraction              | number        | 否       | 0            | [0, 1]       | `trace_id_ratio`：采样策略的百分比。 |
| sampler.options.root                  | object        | 否       | -            | -            | `parent_base`：采样策略在没有上游 tracing 时，会使用 root 采样策略做决策。|
| sampler.options.root.name             | string        | 否       | -            | ["always_on", "always_off", "trace_id_ratio"] | root 采样策略。 |
| sampler.options.root.options          | object        | 否       | -            | -            | root 采样策略参数。 |
| sampler.options.root.options.fraction | number        | 否       | 0            | [0, 1]       | `trace_id_ratio` root 采样策略的百分比|
| additional_attributes                 | array[string] | 否       | -            | -            | 追加到 trace span 的额外属性，支持内置 NGINX 或 [APISIX 变量](https://apisix.apache.org/docs/apisix/apisix-variable/)。|
| additional_header_prefix_attributes   | array[string] | 否       | -            | -            | 附加到跟踪范围属性的标头或标头前缀。例如，使用 `x-my-header"` 或 `x-my-headers-*` 来包含带有前缀 `x-my-headers-` 的所有标头。 |

## 示例

以下示例展示了如何在不同场景下使用 `opentelemetry` 插件。

### 启用全面的请求生命周期追踪

:::note

开启全面追踪会在请求生命周期的各个阶段引入 span 的创建与上报开销，会对 APISIX 吞吐量和延迟产生影响。

:::

要在请求生命周期的各个阶段（包括 SSL/SNI、access、header/body filter、upstream 以及 logging）启用全面追踪，请在配置文件中将 `tracing` 字段设置为 `true`：

```yaml title="config.yaml"
apisix:
  tracing: true
```

### 启用 opentelemetry 插件

默认情况下，APISIX 中的 `opentelemetry` 插件是禁用的。要启用它，请将插件添加到配置文件中，如下所示：

```yaml title="config.yaml"
plugins:
  - ...
  - opentelemetry
```

重新加载 APISIX 以使更改生效。

### 将 Traces 上报到 OpenTelemetry

以下示例展示了如何追踪对路由的请求并将 traces 发送到 OpenTelemetry。

在 Docker 启动一个 OpenTelemetry collector 实例：

```shell
docker run -d --name otel-collector -p 4318:4318 otel/opentelemetry-collector-contrib
```

创建一个开启了 `opentelemetry` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "otel-tracing-route",
    "uri": "/anything",
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        }
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

在 OpenTelemetry collector 的日志中，你应该看到类似以下的信息：

```text
2024-02-18T17:14:03.825Z info ResourceSpans #0
ScopeSpans #0
ScopeSpans SchemaURL:
InstrumentationScope opentelemetry-lua
Span #0
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 905f850f13e32bfb
    ID             : 5a3835b61110d942
    Name           : http_router_match
    Kind           : Internal
    Start time     : 2025-10-24 06:58:04.430430976 +0000 UTC
    End time       : 2025-10-24 06:58:04.431542016 +0000 UTC
    Status code    : Unset
    Status message :
Span #1
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 905f850f13e32bfb
    ID             : 4ab25e2b92f394e1
    Name           : resolve_dns
    Kind           : Internal
    Start time     : 2025-10-24 06:58:04.432521984 +0000 UTC
    End time       : 2025-10-24 06:58:04.44903296 +0000 UTC
    Status code    : Unset
    Status message :
Span #2
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 905f850f13e32bfb
    ID             : 3620c0f05dd2be4f
    Name           : apisix.phase.header_filter
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.960481024 +0000 UTC
    End time       : 2025-10-24 06:58:06.960510976 +0000 UTC
    Status code    : Unset
    Status message :
Span #3
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 4c5f3476f62a7e8a
    ID             : a9bfad7bb6986e41
    Name           : apisix.phase.body_filter
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.960579072 +0000 UTC
    End time       : 2025-10-24 06:58:06.96059008 +0000 UTC
    Status code    : Unset
    Status message :
Span #4
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : b2994675df6baa83
    ID             : 26705f9c47584a5b
    Name           : apisix.phase.delayed_body_filter.opentelemetry
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.960613888 +0000 UTC
    End time       : 2025-10-24 06:58:06.960687104 +0000 UTC
    Status code    : Unset
    Status message :
Span #5
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 4c5f3476f62a7e8a
    ID             : b2994675df6baa83
    Name           : apisix.phase.delayed_body_filter
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.96059904 +0000 UTC
    End time       : 2025-10-24 06:58:06.960692992 +0000 UTC
    Status code    : Unset
    Status message :
Span #6
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 905f850f13e32bfb
    ID             : 4c5f3476f62a7e8a
    Name           : apisix.phase.body_filter
    Kind           : Server
    Start time     : 2025-10-24 06:58:06.96056704 +0000 UTC
    End time       : 2025-10-24 06:58:06.960698112 +0000 UTC
    Status code    : Unset
    Status message :
Span #7
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 2024d73d32cbd81b
    ID             : 223c64fb691a24e8
    Name           : apisix.phase.body_filter
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.961624064 +0000 UTC
    End time       : 2025-10-24 06:58:06.961635072 +0000 UTC
    Status code    : Unset
    Status message :
Span #8
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : fd193dd24c618f60
    ID             : 8729ad6e0d94a23b
    Name           : apisix.phase.delayed_body_filter.opentelemetry
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.961648896 +0000 UTC
    End time       : 1970-01-01 00:00:00 +0000 UTC
    Status code    : Unset
    Status message :
Span #9
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 2024d73d32cbd81b
    ID             : fd193dd24c618f60
    Name           : apisix.phase.delayed_body_filter
    Kind           : Internal
    Start time     : 2025-10-24 06:58:06.961641984 +0000 UTC
    End time       : 1970-01-01 00:00:00 +0000 UTC
    Status code    : Unset
    Status message :
Span #10
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : 905f850f13e32bfb
    ID             : 2024d73d32cbd81b
    Name           : apisix.phase.body_filter
    Kind           : Server
    Start time     : 2025-10-24 06:58:06.960980992 +0000 UTC
    End time       : 1970-01-01 00:00:00 +0000 UTC
    Status code    : Unset
    Status message :
Span #11
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      : cfb0b4603dc2e385
    ID             : 905f850f13e32bfb
    Name           : apisix.phase.access
    Kind           : Server
    Start time     : 2025-10-24 06:58:04.427932928 +0000 UTC
    End time       : 1970-01-01 00:00:00 +0000 UTC
    Status code    : Unset
    Status message :
Span #12
    Trace ID       : 95a1644afaaf65e1f0193b1f193b990a
    Parent ID      :
    ID             : cfb0b4603dc2e385
    Name           : GET /headers
    Kind           : Server
    Start time     : 2025-10-24 06:58:04.432427008 +0000 UTC
    End time       : 2025-10-24 06:58:06.962299904 +0000 UTC
    Status code    : Unset
    Status message :
Attributes:
     -> net.host.name: Str(127.0.0.1)
     -> http.method: Str(GET)
     -> http.scheme: Str(http)
     -> http.target: Str(/headers)
     -> http.user_agent: Str(curl/8.16.0)
     -> apisix.route_id: Str(otel-tracing-route)
     -> apisix.route_name: Empty()
     -> http.route: Str(/headers)
     -> http.status_code: Int(200)
{"resource": {"service.instance.id": "5006c483-d64c-4d1d-87ac-edb037ba3669", "service.name": "otelcol-contrib", "service.version": "0.138.0"}, "otelcol.component.id": "debug", "otelcol.component.kind": "exporter", "otelcol.signal": "traces"}
2025-10-24T06:58:13.893Z	info	Metrics	{"resource": {"service.instance.id": "5006c483-d64c-4d1d-87ac-edb037ba3669", "service.name": "otelcol-contrib", "service.version": "0.138.0"}, "otelcol.component.id": "debug", "otelcol.component.kind": "exporter", "otelcol.signal": "metrics", "resource metrics": 1, "metrics": 25, "data points": 26}
2025-10-24T06:58:13.893Z	info	ResourceMetrics #0
```

要可视化这些追踪，你可以将 traces 导出到后端服务，例如 Zipkin 和 Prometheus。有关更多详细信息，请参阅[exporters](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter)。

### 在日志中使用 trace 变量

以下示例展示了如何配置 `opentelemetry` 插件以设置以下内置变量，这些变量可以在日志插件或访问日志中使用：

- `opentelemetry_context_traceparent`:  [W3C trace context](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format)
- `opentelemetry_trace_id`: 当前 span 的 trace_id
- `opentelemetry_span_id`: 当前 span 的 span_id

配置插件元数据以将 `set_ngx_var` 设置为 true：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/opentelemetry -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "set_ngx_var": true
}'
```

如下更新配置文件。你应该自定义访问日志格式以使用 `opentelemetry` 插件变量，并在 `set_ngx_var` 字段中设置 `opentelemetry` 变量。

```yaml title="conf/config.yaml"
nginx_config:
  http:
    enable_access_log: true
    access_log_format: '{"time": "$time_iso8601","opentelemetry_context_traceparent": "$opentelemetry_context_traceparent","opentelemetry_trace_id": "$opentelemetry_trace_id","opentelemetry_span_id": "$opentelemetry_span_id","remote_addr": "$remote_addr"}'
    access_log_format_escape: json
```

重新加载 APISIX 以使配置更改生效。

```text
{"time": "18/Feb/2024:15:09:00 +0000","opentelemetry_context_traceparent": "00-fbd0a38d4ea4a128ff1a688197bc58b0-8f4b9d9970a02629-01","opentelemetry_trace_id": "fbd0a38d4ea4a128ff1a688197bc58b0","opentelemetry_span_id": "af3dc7642104748a","remote_addr": "172.10.0.1"}
```
