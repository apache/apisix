---
title: opentelemetry
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

[OpenTelemetry](https://opentelemetry.io/) 提供符合 [opentelemetry specification](https://github.com/open-telemetry/opentelemetry-specification) 协议规范的 Tracing 数据上报。

只支持 `HTTP` 协议，且请求类型为 `application/x-protobuf` 的数据上报，相关协议标准：[OTLP/HTTP Request](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md#otlphttp-request)。

## 属性

| 名称         | 类型   | 必选项 | 默认值   | 有效值       | 描述                                                  |
| ------------ | ------ | ------ | -------- | ------------ | ----------------------------------------------------- |
| sampler | object | 可选 | | | 采样配置
| sampler.name | string | 可选 | always_off | ["always_on", "always_off", "trace_id_ratio", "parent_base"] | 采样算法，always_on：全采样；always_off：不采样；trace_id_ratio：基于 trace id 的百分比采样；parent_base：如果存在 tracing 上游，则使用上游的采样决定，否则使用配置的采样算法决策
| sampler.options | object | 可选 | | {fraction = 0, root = {name = "always_off"}} | 采样算法参数
| sampler.options.fraction | number | 可选 | 0 | [0, 1] | trace_id_ratio 采样算法的百分比
| sampler.options.root | object | 可选 | {name = "always_off", options = {fraction = 0}} | | parent_base 采样算法在没有上游 tracing 时，会使用 root 采样算法做决策
| sampler.options.root.name | string | 可选 | always_off | ["always_on", "always_off", "trace_id_ratio"] | 采样算法
| sampler.options.root.options | object | 可选 | {fraction = 0} | | 采样算法参数
| sampler.options.root.options.fraction | number | 可选 | 0 | [0, 1] | trace_id_ratio 采样算法的百分比
| additional_attributes | array[string] | optional | | | 追加到 trace span 的额外属性（变量名为 key，变量值为 value）
| additional_attributes[0] | string | required | | | APISIX or Nginx 变量，例如 `http_header` or `route_id`

## 如何启用

首先，你需要在 `config.yaml` 里面启用 opentelemetry 插件：

```yaml
# 加到 config.yaml
plugins:
  - ... # plugin you need
  - opentelemetry
```

然后重载 APISIX。

下面是一个示例，在指定的 route 上开启了 opentelemetry 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            "10.110.149.175:8089": 1
        }
    }
}'
```

## 如何设置数据上报

我们可以通过指定 `conf/config.yaml` 中的配置来设置数据上报：

| 名称         | 类型   | 默认值   | 描述                                                  |
| ------------ | ------ | -------- | ----------------------------------------------------- |
| trace_id_source | enum | random | 合法的取值：`random` 或 `x-request-id`，允许使用当前请求 ID 代替随机 ID 作为新的 TraceID，必须确保当前请求 ID 是符合 TraceID 规范的：`[0-9a-f]{32}` |
| resource | object |   | 追加到 trace 的额外 [resource](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md) |
| collector | object | {address = "127.0.0.1:4317", request_timeout = 3} | 数据采集服务 |
| collector.address | string | 127.0.0.1:4317 | 数据采集服务地址 |
| collector.request_timeout | integer | 3 | 数据采集服务上报请求超时时长，单位秒 |
| collector.request_headers | object |  | 数据采集服务上报请求附加的 HTTP 请求头 |
| batch_span_processor | object |  | trace span 处理器参数配置 |
| batch_span_processor.drop_on_queue_full | boolean | true | 当处理器缓存队列慢试，丢弃新到来的 span |
| batch_span_processor.max_queue_size | integer | 2048 | 处理器缓存队列容量最大值 |
| batch_span_processor.batch_timeout | number | 5 | 构造一批 span 超时时长，单位秒 |
| batch_span_processor.max_export_batch_size | integer | 256 | 一批 span 的数量，每次上报的 span 数量 |
| batch_span_processor.inactive_timeout | number | 2 | 每隔多长时间检查是否有一批 span 可以上报，单位秒 |

配置示例:

```yaml
plugin_attr:
  opentelemetry:
    resource:
      service.name: APISIX
      tenant.id: business_id
    collector:
      address: 192.168.8.211:4317
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

## 禁用插件

当你想禁用一条路由/服务上的 opentelemetry 插件的时候，很简单，在插件的配置中把对应的 JSON 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            "10.110.149.175:8089": 1
        }
    }
}'
```
