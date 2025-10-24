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
