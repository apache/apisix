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

The `opentelemetry` Plugin can be used to report tracing data according to the [OpenTelemetry Specification](https://opentelemetry.io/docs/reference/specification/).

The Plugin only supports binary-encoded [OLTP over HTTP](https://opentelemetry.io/docs/reference/specification/protocol/otlp/#otlphttp).

## Configurations

By default, configurations of the Service name, tenant ID, collector, and batch span processor are pre-configured in [default configuration](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua).

You can change this configuration of the Plugin through the endpoint `apisix/admin/plugin_metadata/opentelemetry` For example:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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

## Attributes

| Name                                  | Type          | Required | Default      | Valid Values | Description |
|---------------------------------------|---------------|----------|--------------|--------------|-------------|
| sampler                               | object        | False    | -            | -            | Sampling configuration. |
| sampler.name                          | string        | False    | `always_off` | ["always_on", "always_off", "trace_id_ratio", "parent_base"]  | Sampling strategy.<br />To always sample, use `always_on`.<br />To never sample, use `always_off`.<br />To randomly sample based on a given ratio, use `trace_id_ratio`.<br />To use the sampling decision of the span's parent, use `parent_base`. If there is no parent, use the root sampler. |
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

### Enable Comprehensive Request Lifecycle Tracing

:::note

Enabling comprehensive tracing adds span creation and export overhead across the request lifecycle, which may impact throughput and latency.

:::

To enable comprehensive tracing across the request lifecycle (SSL/SNI, rewrite/access, header_filter/body_filter, and log), set the `tracing` field to `true` in the configuration file:

```yaml title="config.yaml"
apisix:
  tracing: true
```

### Enable `opentelemetry` Plugin

By default, the `opentelemetry` Plugin is disabled in APISIX. To enable, add the Plugin to your configuration file as such:

```yaml title="config.yaml"
plugins:
  - ...
  - opentelemetry
```

Reload APISIX for changes to take effect.

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
info	ResourceSpans #0
Resource SchemaURL: 
Resource attributes:
     -> telemetry.sdk.language: Str(lua)
     -> telemetry.sdk.name: Str(opentelemetry-lua)
     -> telemetry.sdk.version: Str(0.1.1)
     -> hostname: Str(RC)
     -> service.name: Str(APISIX)
ScopeSpans #0
ScopeSpans SchemaURL: 
InstrumentationScope opentelemetry-lua 
Span #0
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : b125e88a4ed7e409
    ID             : 5e1d6b61c31220c9
    Name           : http_router_match
    Kind           : Internal
    Start time     : 2026-02-04 00:55:09.468541952 +0000 UTC
    End time       : 2026-02-04 00:55:09.468577024 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #1
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 8b00441884e3908f
    ID             : b125e88a4ed7e409
    Name           : apisix.phase.access
    Kind           : Server
    Start time     : 2026-02-04 00:55:09.468467968 +0000 UTC
    End time       : 2026-02-04 00:55:09.469076992 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #2
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 8b00441884e3908f
    ID             : f603a09f54520f8b
    Name           : resolve_dns
    Kind           : Internal
    Start time     : 2026-02-04 00:55:09.469084928 +0000 UTC
    End time       : 2026-02-04 00:55:09.469104896 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #3
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 8b00441884e3908f
    ID             : 303694d8fc044ab2
    Name           : apisix.phase.header_filter
    Kind           : Server
    Start time     : 2026-02-04 00:55:09.470095872 +0000 UTC
    End time       : 2026-02-04 00:55:09.470138112 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #4
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 8b00441884e3908f
    ID             : 078f82f64325c684
    Name           : apisix.phase.body_filter
    Kind           : Server
    Start time     : 2026-02-04 00:55:09.470141952 +0000 UTC
    End time       : 2026-02-04 00:55:09.47021696 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #5
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 8b00441884e3908f
    ID             : fb6fba6b28496598
    Name           : apisix.phase.log.plugins.opentelemetry
    Kind           : Internal
    Start time     : 2026-02-04 00:55:09.470256896 +0000 UTC
    End time       : 2026-02-04 00:55:09.479666944 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Span #6
    Trace ID       : 6cd24a1d178f836f43de423a45ead766
    Parent ID      : 
    ID             : 8b00441884e3908f
    Name           : GET /anything
    Kind           : Server
    Start time     : 2026-02-04 00:55:09.468459008 +0000 UTC
    End time       : 2026-02-04 00:55:09.480956928 +0000 UTC
    Status code    : Unset
    Status message : 
    DroppedAttributesCount: 0
    DroppedEventsCount: 0
    DroppedLinksCount: 0
Attributes:
     -> net.host.name: Str(localhost)
     -> http.method: Str(GET)
     -> http.scheme: Str(http)
     -> http.target: Str(/anything)
     -> http.user_agent: Str(curl/7.81.0)
     -> apisix.route_id: Str(otel-tracing-route)
     -> apisix.route_name: Empty()
     -> http.route: Str(/anything)
     -> http.status_code: Int(200)
     -> http.response.status_code: Int(200)
	{"resource": {"service.instance.id": "6f63899f-6fda-42db-a18b-b0892a77958a", "service.name": "otelcol-contrib", "service.version": "0.144.0"}, "otelcol.component.id": "debug", "otelcol.component.kind": "exporter", "otelcol.signal": "traces"}
```

To visualize these traces, you can export your telemetry to backend Services, such as Zipkin and Prometheus. See [exporters](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter) for more details.

### Using Trace Variables in Logging

The following example demonstrates how to configure the `opentelemetry` Plugin to set the following built-in variables, which can be used in logger Plugins or access logs:

- `opentelemetry_context_traceparent`: [trace parent](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format) ID
- `opentelemetry_trace_id`: trace ID of the current span
- `opentelemetry_span_id`: span ID of the current span

Configure the plugin metadata to set `set_ngx_var` as true:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/opentelemetry -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "set_ngx_var": true
}'
```

Update the configuration file as below. You should customize the access log format to use the `opentelemetry` Plugin variables.

```yaml title="conf/config.yaml"
nginx_config:
  http:
    enable_access_log: true
    access_log_format: '{"time": "$time_iso8601","opentelemetry_context_traceparent": "$opentelemetry_context_traceparent","opentelemetry_trace_id": "$opentelemetry_trace_id","opentelemetry_span_id": "$opentelemetry_span_id","remote_addr": "$remote_addr"}'
    access_log_format_escape: json
```

Reload APISIX for configuration changes to take effect.

You should see access log entries similar to the following when you generate requests:

```text
{"time": "18/Feb/2024:15:09:00 +0000","opentelemetry_context_traceparent": "00-fbd0a38d4ea4a128ff1a688197bc58b0-8f4b9d9970a02629-01","opentelemetry_trace_id": "fbd0a38d4ea4a128ff1a688197bc58b0","opentelemetry_span_id": "af3dc7642104748a","remote_addr": "172.10.0.1"}
```
