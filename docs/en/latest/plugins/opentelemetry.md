---
title: OpenTelemetry
keywords:
  - APISIX
  - Observability
  - OpenTelemetry
  - API Gateway
description: OpenTelemetry is an open source Observability project. Follow this documentation to integrate OpenTelemetry with API gateway Apache APISIX to measure application performance.
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

## Description

[OpenTelemetry](https://opentelemetry.io) is a vendor-neutral open source [Observability](https://opentelemetry.io/docs/concepts/observability-primer/#what-is-observability) project, and it contains a collection of tools, APIs, and SDKs. We use it to generate, collect, and export telemetry data (metrics, logs, and traces) to analyze software's performance and behavior.

OpenTelemetry provides an [OTEL collector](https://opentelemetry.io/docs/collector/) to process and export telemetry data in multiple formats, which are supported by [Jaeger](https://www.jaegertracing.io/) and [Zipkin](https://zipkin.io/). Also, please read OpenTelemetry's [Specification](https://opentelemetry.io/docs/reference/specification/) to learn and understand the essential fundamental terms.

:::info

The plugin only supports binary-encoded [OLTP over HTTP](https://opentelemetry.io/docs/reference/specification/protocol/otlp/#otlphttp) currently.

:::

## Load Plugin

APISIX doesn't load the `opentelemetry` plugin by default because of the `conf/config-default.yaml` file. Follow the steps to load it:

1. Open the `conf/config-default.yaml` file, and copy the `plugins` field with **all plugin names** to the `conf/config.yaml` file.
2. Uncomment the `#- opentelemetry` line or remove the `#`.
3. Follow the [Plugin Hot Reload Guide](/docs/apisix/terminology/plugin/#hot-reload) to reload plugins.

```yaml title="conf/config.yaml"
plugins:
  - ...
  - opentelemetry
  - ...
```

## Plugin YAML Attributes

:::info

This section is optional.

:::

There have some default YAML configurations in the `conf/config-default.yaml` file, e.g., Collector, Processors. We should update them in the `config.yaml` file.

1. Open the `conf/config-default.yaml` file, and coply the `plugin_attr.opentelemetry.xxx` field to the `conf/config.yaml` file.

```yaml title="conf/config.yaml"
plugin_attr:
  opentelemetry:
    ...
    collector:
      address: 127.0.0.1:4318
    ...
```

2. Update configurations as needed.
3. Follow the [Plugin Hot Reload Guide](/docs/apisix/terminology/plugin/#hot-reload) to reload plugins.

### Attributes

| Name                                       | Type    | Default                                           | Description                                                                                                                                                                                                                   |
| ------------------------------------------ | ------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| trace_id_source                            | enum    | random                                            | Source of the trace ID. Valid values are `random` or `x-request-id`. When set to `x-request-id`, the value of the `x-request-id` header will be used as trace ID. Make sure that is matches the regex pattern `[0-9a-f]{32}`. |
| resource                                   | object  |                                                   | Additional [resource](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md) appended to the trace.                                                                           |
| collector                                  | object  | {address = "127.0.0.1:4318", request_timeout = 3} | OpenTelemetry Collector configuration.                                                                                                                                                                                        |
| collector.address                          | string  | 127.0.0.1:4318                                    | Collector address.                                                                                                                                                                                                            |
| collector.request_timeout                  | integer | 3                                                 | Report request timeout in seconds.                                                                                                                                                                                            |
| collector.request_headers                  | object  |                                                   | Report request HTTP headers.                                                                                                                                                                                                  |
| batch_span_processor                       | object  |                                                   | Trace span processor.                                                                                                                                                                                                         |
| batch_span_processor.drop_on_queue_full    | boolean | true                                              | When set to `true`, drops the span when queue is full. Otherwise, force process batches.                                                                                                                                      |
| batch_span_processor.max_queue_size        | integer | 2048                                              | Maximum queue size for buffering spans for delayed processing.                                                                                                                                                                |
| batch_span_processor.batch_timeout         | number  | 5                                                 | Maximum time in seconds for constructing a batch.                                                                                                                                                                             |
| batch_span_processor.max_export_batch_size | integer | 256                                               | Maximum number of spans to process in a single batch.                                                                                                                                                                         |
| batch_span_processor.inactive_timeout      | number  | 2                                                 | Time interval in seconds between processing batches.                                                                                                                                                                          |

## Plugin Attributes

:::tip

Use the following attributes to create a Route, Service or Global Plugin.

:::

| Name                                  | Type          | Required | Default                                         | Valid values                                                 | Description                                                                                                                                                                                                                                  |
| ------------------------------------- | ------------- | -------- | ----------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| sampler                               | object        | False    |                                                 |                                                              | Sampling configuration.                                                                                                                                                                                                                      |
| sampler.name                          | string        | False    | always_off                                      | ["always_on", "always_off", "trace_id_ratio", "parent_base"] | Sampling strategy. `always_on`: always samples, `always_off`: never samples, `trace_id_ratio`: random sampling result based on given sampling probability, `parent_base`: use parent decision if given, else determined by the root sampler. |
| sampler.options                       | object        | False    |                                                 | {fraction = 0, root = {name = "always_off"}}                 | Parameters for sampling strategy.                                                                                                                                                                                                            |
| sampler.options.fraction              | number        | False    | 0                                               | [0, 1]                                                       | Sampling probability for `trace_id_ratio`.                                                                                                                                                                                                   |
| sampler.options.root                  | object        | False    | {name = "always_off", options = {fraction = 0}} |                                                              | Root sampler for `parent_base` strategy.                                                                                                                                                                                                     |
| sampler.options.root.name             | string        | False    | always_off                                      | ["always_on", "always_off", "trace_id_ratio"]                | Root sampling strategy.                                                                                                                                                                                                                      |
| sampler.options.root.options          | object        | False    | {fraction = 0}                                  |                                                              | Root sampling strategy parameters.                                                                                                                                                                                                           |
| sampler.options.root.options.fraction | number        | False    | 0                                               | [0, 1]                                                       | Root sampling probability for `trace_id_ratio`.                                                                                                                                                                                              |
| additional_attributes                 | array[string] | False    |                                                 |                                                              | Variables and its values which will be appended to the trace span.                                                                                                                                                                           |
| additional_attributes[0]              | string        | False    |                                                 |                                                              | APISIX or Nginx variables. For example, `http_header` or `route_id`.                                                                                                                                                                         |

## Enable Plugin

:::tip

Read more: [How to integrate OpenTelemetry with Apache APISIX](https://apisix.apache.org/blog/2022/02/28/apisix-integration-opentelemetry-plugin/)

:::

Now, you can enable the Plugin on a specific Route:

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
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Disable Plugin

To disable this plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
