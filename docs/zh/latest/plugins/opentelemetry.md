---
title: opentelemetry
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - OpenTelemetry
description: 本文介绍了关于 Apache APISIX `opentelemetry` 插件的基本信息及使用方法。
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

`opentelemetry` 插件可用于根据 [OpenTelemetry specification](https://opentelemetry.io/docs/reference/specification/) 协议规范上报 Tracing 数据。

该插件仅支持二进制编码的 [OLTP over HTTP](https://opentelemetry.io/docs/reference/specification/protocol/otlp/#otlphttp)，即请求类型为 `application/x-protobuf` 的数据上报。

## 属性

| 名称                                  | 类型           | 必选项 | 默认值                                           | 有效值                                                      | 描述                                                  |
| ------------------------------------- | ------------- | ------ | ----------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| sampler                               | object        | 否     |                                                 |                                                              | 采样策略。 |
| sampler.name                          | string        | 否     | always_off                                      | ["always_on", "always_off", "trace_id_ratio", "parent_base"] | 采样策略。`always_on`：全采样；`always_off`：不采样；`trace_id_ratio`：基于 trace id 的百分比采样；`parent_base`：如果存在 tracing 上游，则使用上游的采样决定，否则使用配置的采样策略决策。 |
| sampler.options                       | object        | 否     |                                                 | {fraction = 0, root = {name = "always_off"}}                 | 采样策略参数。 |
| sampler.options.fraction              | number        | 否     | 0                                               | [0, 1]                                                       | `trace_id_ratio` 采样策略的百分比。 |
| sampler.options.root                  | object        | 否     | {name = "always_off", options = {fraction = 0}} |                                                              | `parent_base` 采样策略在没有上游 tracing 时，会使用 root 采样策略做决策。 |
| sampler.options.root.name             | string        | 否     | always_off                                      | ["always_on", "always_off", "trace_id_ratio"]                | root 采样策略。 |
| sampler.options.root.options          | object        | 否     | {fraction = 0}                                  |                                                              | root 采样策略参数。 |
| sampler.options.root.options.fraction | number        | 否     | 0                                               | [0, 1]                                                       | `trace_id_ratio` root 采样策略的百分比 |
| additional_attributes                 | array[string] | 否     |                                                 |                                                              | 追加到 trace span 的额外属性，支持内置 NGINX 或 APISIX 变量，例如：`http_header` 或者 `route_id`。 |
| additional_header_prefix_attributes   | array[string] | False    |                                                 |                                                              | 附加到跟踪范围属性的标头或标头前缀。例如，使用 `x-my-header"` 或 `x-my-headers-*` 来包含带有前缀 `x-my-headers-` 的所有标头。                                                                                                                                                                   |

## 如何设置数据上报

你可以通过在 `conf/config.yaml` 中指定配置来设置数据上报：

| 名称                                       | 类型    | 默认值                                             | 描述                                                                                                                                             |
| ------------------------------------------ | ------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| trace_id_source                            | enum    | random                                            | trace ID 的来源。有效值为：`random` 或 `x-request-id`。当设置为 `x-request-id` 时，`x-request-id` 头的值将用作跟踪 ID。请确保当前请求 ID 是符合 TraceID 规范的：`[0-9a-f]{32}`。 |
| resource                                   | object  |                                                   | 追加到 trace 的额外 [resource](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md)。 |
| collector                                  | object  | {address = "127.0.0.1:4318", request_timeout = 3} | OpenTelemetry Collector 配置。 |
| collector.address                          | string  | 127.0.0.1:4318                                    | 数据采集服务的地址。如果数据采集服务使用的是 HTTPS 协议，可以将 address 设置为 https://127.0.0.1:4318。 |
| collector.request_timeout                  | integer | 3                                                 | 数据采集服务上报请求超时时长，单位为秒。 |
| collector.request_headers                  | object  |                                                   | 数据采集服务上报请求附加的 HTTP 请求头。 |
| batch_span_processor                       | object  |                                                   | trace span 处理器参数配置。 |
| batch_span_processor.drop_on_queue_full    | boolean | true                                              | 如果设置为 `true` 时，则在队列排满时删除 span。否则，强制处理批次。|
| batch_span_processor.max_queue_size        | integer | 2048                                              | 处理器缓存队列容量的最大值。 |
| batch_span_processor.batch_timeout         | number  | 5                                                 | 构造一批 span 超时时间，单位为秒。 |
| batch_span_processor.max_export_batch_size | integer | 256                                               | 单个批次中要处理的 span 数量。 |
| batch_span_processor.inactive_timeout      | number  | 2                                                 | 两个处理批次之间的时间间隔，单位为秒。 |

你可以参考以下示例进行配置：

```yaml title="./conf/config.yaml"
plugin_attr:
  opentelemetry:
    resource:
      service.name: APISIX
      tenant.id: business_id
    collector:
      address: 192.168.8.211:4318
      request_timeout: 3
      request_headers:
        foo: bar
    batch_span_processor:
      drop_on_queue_full: false
      max_queue_size: 6
      batch_timeout: 2
      inactive_timeout: 1
      max_export_batch_size: 2
```

## 如何使用变量

以下`nginx`变量是由`opentelemetry` 设置的。

- `opentelemetry_context_traceparent` -  [W3C trace context](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format), 例如：`00-0af7651916cd43dd8448eb211c80319c-b9c7c989f97918e1-01`
- `opentelemetry_trace_id` - 当前 span 的 trace_id
- `opentelemetry_span_id` - 当前 span 的 span_id

如何使用？你需要在配置文件（`./conf/config.yaml`）设置如下：

```yaml title="./conf/config.yaml"
http:
    enable_access_log: true
    access_log: "/dev/stdout"
    access_log_format: '{"time": "$time_iso8601","opentelemetry_context_traceparent": "$opentelemetry_context_traceparent","opentelemetry_trace_id": "$opentelemetry_trace_id","opentelemetry_span_id": "$opentelemetry_span_id","remote_addr": "$remote_addr","uri": "$uri"}'
    access_log_format_escape: json
plugins:
  - opentelemetry
plugin_attr:
  opentelemetry:
    set_ngx_var: true
```

## 如何启用

`opentelemetry` 插件默认为禁用状态，你需要在配置文件（`./conf/config.yaml`）中开启该插件：

```yaml title="./conf/config.yaml"
plugins:
  - ... # plugin you need
  - opentelemetry
```

开启成功后，可以通过如下命令在指定路由上启用 `opentelemetry` 插件：

:::note

您可以像这样从 config.yaml 中获取 admin_key 。

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/uid/*"
    ],
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
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 删除插件

当你需要禁用 `opentelemetry` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/uid/*"
    ],
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
