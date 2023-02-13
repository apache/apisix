---
title: opentelemetry
keywords:
  - APISIX
  - Plugin
  - OpenTelemetry
  - opentelemetry
description: This document contains information about the Apache opentelemetry Plugin.
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

The `opentelemetry` Plugin can be used to report tracing data according to the [OpenTelemetry specification](https://opentelemetry.io/docs/reference/specification/).

The Plugin only supports binary-encoded [OLTP over HTTP](https://opentelemetry.io/docs/reference/specification/protocol/otlp/#otlphttp).

## Attributes

| Name                                  | Type          | Required | Default                                         | Valid values                                                 | Description                                                                                                                                                                                                                                  |
|---------------------------------------|---------------|----------|-------------------------------------------------|--------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| sampler                               | object        | False    |                                                 |                                                              | Sampling configuration.                                                                                                                                                                                                                      |
| sampler.name                          | string        | False    | always_off                                      | ["always_on", "always_off", "trace_id_ratio", "parent_base"] | Sampling strategy. `always_on`: always samples, `always_off`: never samples, `trace_id_ratio`: random sampling result based on given sampling probability, `parent_base`: use parent decision if given, else determined by the root sampler. |
| sampler.options                       | object        | False    |                                                 | {fraction = 0, root = {name = "always_off"}}                 | Parameters for sampling strategy.                                                                                                                                                                                                            |
| sampler.options.fraction              | number        | False    | 0                                               | [0, 1]                                                       | Sampling probability for `trace_id_ratio`.                                                                                                                                                                                                   |
| sampler.options.root                  | object        | False    | {name = "always_off", options = {fraction = 0}} |                                                              | Root sampler for `parent_base` strategy.                                                                                                                                                                                                     |
| sampler.options.root.name             | string        | False    | always_off                                      | ["always_on", "always_off", "trace_id_ratio"]                | Root sampling strategy.                                                                                                                                                                                                                      |
| sampler.options.root.options          | object        | False    | {fraction = 0}                                  |                                                              | Root sampling strategy parameters.                                                                                                                                                                                                           |
| sampler.options.root.options.fraction | number        | False    | 0                                               | [0, 1]                                                       | Root sampling probability for `trace_id_ratio`.                                                                                                                                                                                              |
| additional_attributes                 | array[string] | False    |                                                 |                                                              | Variables and its values which will be appended to the trace span.                                                                                                                                                                           |
| additional_attributes[0]              | string        | True     |                                                 |                                                              | APISIX or Nginx variables. For example, `http_header` or `route_id`.                                                                                                                                                                         |
| additional_header_prefix_attributes   | array[string] | False    |                                                 |                                                              | Headers or headers prefixes to be appended to the trace span's attributes.                                                                                                                                                                   |
| additional_header_prefix_attributes[0]| string        | True     |                                                 |                                                              | Request headers. For example, `x-my-header"` or `x-my-headers-*` to include all headers with the prefix `x-my-headers-`.                                                                                                                     |

### Configuring the collector

You can set up the collector by configuring it in you configuration file (`conf/config.yaml`):

| Name                                       | Type    | Default                                           | Description                                                                                                                                                                                                                   |
|--------------------------------------------|---------|---------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| trace_id_source                            | enum    | random                                            | Source of the trace ID. Valid values are `random` or `x-request-id`. When set to `x-request-id`, the value of the `x-request-id` header will be used as trace ID. Make sure that is matches the regex pattern `[0-9a-f]{32}`. |
| resource                                   | object  |                                                   | Additional [resource](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md) appended to the trace.                                                                           |
| collector                                  | object  | {address = "127.0.0.1:4318", request_timeout = 3} | OpenTelemetry Collector configuration.                                                                                                                                                                                        |
| collector.address                          | string  | 127.0.0.1:4318                                    | Collector address. If the collector serves on https, use https://127.0.0.1:4318 as the address.                                                                                                                                    |
| collector.request_timeout                  | integer | 3                                                 | Report request timeout in seconds.                                                                                                                                                                                            |
| collector.request_headers                  | object  |                                                   | Report request HTTP headers.                                                                                                                                                                                                  |
| batch_span_processor                       | object  |                                                   | Trace span processor.                                                                                                                                                                                                         |
| batch_span_processor.drop_on_queue_full    | boolean | true                                              | When set to `true`, drops the span when queue is full. Otherwise, force process batches.                                                                                                                                      |
| batch_span_processor.max_queue_size        | integer | 2048                                              | Maximum queue size for buffering spans for delayed processing.                                                                                                                                                                |
| batch_span_processor.batch_timeout         | number  | 5                                                 | Maximum time in seconds for constructing a batch.                                                                                                                                                                             |
| batch_span_processor.max_export_batch_size | integer | 256                                               | Maximum number of spans to process in a single batch.                                                                                                                                                                         |
| batch_span_processor.inactive_timeout      | number  | 2                                                 | Time interval in seconds between processing batches.                                                                                                                                                                          |

You can configure these as shown below:

```yaml title="conf/config.yaml"
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

## Enabling the Plugin

To enable the Plugin, you have to add it to your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - opentelemetry
```

Now, you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

To disable the `opentelemetry` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
