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

## Description

[OpenTelemetry](https://opentelemetry.io/) report Tracing data according to [opentelemetry specification](https://github.com/open-telemetry/opentelemetry-specification).

Just support reporting in `HTTP` with `Content-Type=application/x-protobuf`, the specification: [OTLP/HTTP Request](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md#otlphttp-request)。

## Attributes

| Name         | Type   | Requirement | Default  | Valid        | Description                                                          |
| ------------ | ------ | ------ | -------- | ------------ | ----------------------------------------------------- |
| sampler | object | optional | | | sampling config
| sampler.name | string | optional | always_off | ["always_on", "always_off", "trace_id_ratio", "parent_base"] | sampling strategy，always_on：sampling all；always_off：sampling nothing；trace_id_ratio：base trace id percentage；parent_base：use parent decision, otherwise determined by root
| sampler.options | object | optional | | {fraction = 0, root = {name = "always_off"}} | sampling strategy parameters
| sampler.options.fraction | number | optional | 0 | [0, 1] | trace_id_ratio fraction
| sampler.options.root | object | optional | {name = "always_off", options = {fraction = 0}} | | parent_base root sampler
| sampler.options.root.name | string | optional | always_off | ["always_on", "always_off", "trace_id_ratio"] | sampling strategy
| sampler.options.root.options | object | optional | {fraction = 0} | | sampling strategy parameters
| sampler.options.root.options.fraction | number | optional | 0 | [0, 1] | trace_id_ratio fraction
| additional_attributes | array[string] | optional | | | attributes (variable and its value) which will be appended to the trace span
| additional_attributes[0] | string | required | | | APISIX or Nginx variable, like `http_header` or `route_id`

## How To Enable

First of all, enable the opentelemetry plugin in the `config.yaml`:

```yaml
# Add this in config.yaml
plugins:
  - ... # plugin you need
  - opentelemetry
```

Then reload APISIX.

Here's an example, enable the opentelemetry plugin on the specified route:

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

## How to set collecting

You can set the collecting by specifying the configuration in `conf/config.yaml`.

| Name         | Type   | Default  | Description                                                          |
| ------------ | ------ | -------- | ----------------------------------------------------- |
| trace_id_source | enum | random | the source of trace id, the valid value is `random` or `x-request-id`. If `x-request-id` is set, the value of `x-request-id` request header will be used as trace id. Please make sure it match regex pattern `[0-9a-f]{32}` |
| resource | object |   | additional [resource](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md) append to trace |
| collector | object | {address = "127.0.0.1:4317", request_timeout = 3} | otlp collector |
| collector.address | string | 127.0.0.1:4317 | collector address |
| collector.request_timeout | integer | 3 | report request timeout(second) |
| collector.request_headers | object |  | report request http headers |
| batch_span_processor | object |  | trace span processor |
| batch_span_processor.drop_on_queue_full | boolean | true | drop span when queue is full, otherwise force process batches |
| batch_span_processor.max_queue_size | integer | 2048 | maximum queue size to buffer spans for delayed processing |
| batch_span_processor.batch_timeout | number | 5 | maximum duration(second) for constructing a batch |
| batch_span_processor.max_export_batch_size | integer | 256 | maximum number of spans to process in a single batch |
| batch_span_processor.inactive_timeout | number | 2 | timer interval(second) for processing batches |

Here is an example:

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

## Disable Plugin

When you want to disable the opentelemetry plugin on a route/service, it is very simple,
you can delete the corresponding JSON configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

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
