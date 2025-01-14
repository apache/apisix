---
title: opentelemetry
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - OpenTelemetry
description: The opentelemetry Plugin instruments APISIX and sends traces to OpenTelemetry collector based on the OpenTelemetry specification, in binary-encoded OLTP over HTTP.

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

## Description

The `opentelemetry` Plugin can be used to report tracing data according to the [OpenTelemetry specification](https://opentelemetry.io/docs/reference/specification/).

The Plugin only supports binary-encoded [OLTP over HTTP](https://opentelemetry.io/docs/reference/specification/protocol/otlp/#otlphttp).

## Static Configurations

By default, configurations of the Service name, tenant ID, collector, and batch span processor are pre-configured in [default configuration](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua).

To customize these values, add the corresponding configurations to `config.yaml`. For example:

```yaml
plugin_attr:
  opentelemetry:
    trace_id_source: x-request-id     # Specify the source of the trace ID, `x-request-id` or `random`. When set to `x-request-id`,
                                      # the value of the `x-request-id` header will be used as the trace ID.
    resource:                         # Additional resource to append to the trace.
      service.name: APISIX            # Set the Service name for OpenTelemetry traces.
    collector:
      address: 127.0.0.1:4318       # Set the address of the OpenTelemetry collector to send traces to.
      request_timeout: 3            # Set the timeout for requests to the OpenTelemetry collector in seconds.
      request_headers:              # Set the headers to include in requests to the OpenTelemetry collector.
        Authorization: token        # Set the authorization header to include an access token.
    batch_span_processor:           # Trace span processor.
      drop_on_queue_full: false     # Drop spans when the export queue is full.
      max_queue_size: 1024          # Set the maximum size of the span export queue.
      batch_timeout: 2              # Set the timeout for span batches to wait in the export queue before
                                    # being sent.
      inactive_timeout: 1           # Set the timeout for spans to wait in the export queue before being sent,
                                    # if the queue is not full.
      max_export_batch_size: 16     # Set the maximum number of spans to include in each batch sent to the OpenTelemetry collector.
    set_ngx_var: false              # Export opentelemetry variables to nginx variables.
```

Reload APISIX for changes to take effect.

## Attributes

| Name                                  | Type          | Required | Default      | Valid Values | Description |
|---------------------------------------|---------------|----------|--------------|--------------|-------------|
| sampler                               | object        | False    | -            | -            | Sampling configuration. |
| sampler.name                          | string        | False    | `always_off` | ["always_on", "always_off", "trace_id_ratio", "parent_base"]  | Sampling strategy.<br>To always sample, use `always_on`.<br>To never sample, use `always_off`.<br>To randomly sample based on a given ratio, use `trace_id_ratio`.<br>To use the sampling decision of the span's parent, use `parent_base`. If there is no parent, use the root sampler. |
| sampler.options                       | object        | False    | -            | -            | Parameters for sampling strategy. |
| sampler.options.fraction              | number        | False    | 0            | [0, 1]       | Sampling ratio when the sampling strategy is `trace_id_ratio`. |
| sampler.options.root                  | object        | False    | -            | -            | Root sampler when the sampling strategy is `parent_base` strategy. |
| sampler.options.root.name             | string        | False    | -            | ["always_on", "always_off", "trace_id_ratio"] | Root sampling strategy. |
| sampler.options.root.options          | object        | False    | -            | -            | Root sampling strategy parameters. |
| sampler.options.root.options.fraction | number        | False    | 0            | [0, 1]       | Root sampling ratio when the sampling strategy is `trace_id_ratio`. |
| additional_attributes                 | array[string] | False    | -            | -            | Additional attributes appended to the trace span. Support [built-in variables](https://apisix.apache.org/docs/apisix/apisix-variable/) in values. |
| additional_header_prefix_attributes   | array[string] | False    | -            | -            | Headers or header prefixes appended to the trace span's attributes. For example, use `x-my-header"` or `x-my-headers-*` to include all headers with the prefix `x-my-headers-`. |

## Examples

The examples below demonstrate how you can work with the `opentelemetry` Plugin for different scenarios.

### Enable `opentelemetry` Plugin

By default, the `opentelemetry` Plugin is disabled in APISIX. To enable, add the Plugin to your configuration file as such:

```yaml title="config.yaml"
plugins:
  - ...
  - opentelemetry
```

Reload APISIX for changes to take effect.

See [static configurations](#static-configurations) for other available options you can configure in `config.yaml`.

### Send Traces to OpenTelemetry

The following example demonstrates how to trace requests to a Route and send traces to OpenTelemetry.

Start an OpenTelemetry collector instance in Docker:

```shell
docker run -d --name otel-collector -p 4318:4318 otel/opentelemetry-collector-contrib
```

Create a Route with `opentelemetry` Plugin:

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

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

In OpenTelemetry collector's log, you should see information similar to the following:

```text
2024-02-18T17:14:03.825Z info ResourceSpans #0
Resource SchemaURL:
Resource attributes:
     -> telemetry.sdk.language: Str(lua)
     -> telemetry.sdk.name: Str(opentelemetry-lua)
     -> telemetry.sdk.version: Str(0.1.1)
     -> hostname: Str(e34673e24631)
     -> service.name: Str(APISIX)
ScopeSpans #0
ScopeSpans SchemaURL:
InstrumentationScope opentelemetry-lua
Span #0
    Trace ID       : fbd0a38d4ea4a128ff1a688197bc58b0
    Parent ID      :
    ID             : af3dc7642104748a
    Name           : GET /anything
    Kind           : Server
    Start time     : 2024-02-18 17:14:03.763244032 +0000 UTC
    End time       : 2024-02-18 17:14:03.920229888 +0000 UTC
    Status code    : Unset
    Status message :
Attributes:
     -> net.host.name: Str(127.0.0.1)
     -> http.method: Str(GET)
     -> http.scheme: Str(http)
     -> http.target: Str(/anything)
     -> http.user_agent: Str(curl/7.64.1)
     -> apisix.route_id: Str(otel-tracing-route)
     -> apisix.route_name: Empty()
     -> http.route: Str(/anything)
     -> http.status_code: Int(200)
{"kind": "exporter", "data_type": "traces", "name": "debug"}
```

To visualize these traces, you can export your telemetry to backend Services, such as Zipkin and Prometheus. See [exporters](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter) for more details.

### Using Trace Variables in Logging

The following example demonstrates how to configure the `opentelemetry` Plugin to set the following built-in variables, which can be used in logger Plugins or access logs:

- `opentelemetry_context_traceparent`: [trace parent](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format) ID
- `opentelemetry_trace_id`: trace ID of the current span
- `opentelemetry_span_id`: span ID of the current span

Update the configuration file as below. You should customize the access log format to use the `opentelemetry` Plugin variables, and set `opentelemetry` variables in the `set_ngx_var` field.

```yaml title="conf/config.yaml"
nginx_config:
  http:
    enable_access_log: true
    access_log_format: '{"time": "$time_iso8601","opentelemetry_context_traceparent": "$opentelemetry_context_traceparent","opentelemetry_trace_id": "$opentelemetry_trace_id","opentelemetry_span_id": "$opentelemetry_span_id","remote_addr": "$remote_addr"}'
    access_log_format_escape: json
plugin_attr:
  opentelemetry:
    set_ngx_var: true
```

Reload APISIX for configuration changes to take effect.

You should see access log entries similar to the following when you generate requests:

```text
{"time": "18/Feb/2024:15:09:00 +0000","opentelemetry_context_traceparent": "00-fbd0a38d4ea4a128ff1a688197bc58b0-8f4b9d9970a02629-01","opentelemetry_trace_id": "fbd0a38d4ea4a128ff1a688197bc58b0","opentelemetry_span_id": "af3dc7642104748a","remote_addr": "172.10.0.1"}
```
