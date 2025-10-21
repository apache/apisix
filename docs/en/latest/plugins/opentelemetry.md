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
| trace_plugins                        | boolean       | False    | `false`      | -            | Whether to trace individual plugin execution phases. When enabled, creates child spans for each plugin phase with comprehensive request context attributes. |
| plugin_span_kind                     | string        | False    | `internal`   | ["internal", "server"] | Span kind for plugin execution spans. Some observability providers may exclude internal spans from metrics and dashboards. Use 'server' if you need plugin spans included in service-level metrics. |

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

### Enable Plugin Execution Tracing

The `trace_plugins` attribute allows you to trace individual plugin execution phases. When enabled (set to `true`), the OpenTelemetry plugin creates child spans for each plugin phase (rewrite, access, header_filter, body_filter, log) with comprehensive request context attributes.

**Note**: Plugin tracing is **disabled by default** (`trace_plugins: false`). You must explicitly enable it to see plugin execution spans.

#### Span Kind Configuration

The `plugin_span_kind` attribute allows you to configure the span kind for plugin execution spans. Some observability providers may exclude `internal` spans from metrics and dashboards.

- **Default**: `internal` - Standard internal operation span.
- **Alternative**: `server` - Treated as server-side operation, typically included in service-level metrics

Create a Route with plugin tracing enabled:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/hello",
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        },
        "trace_plugins": true
      },
      "proxy-rewrite": {
        "uri": "/get"
      },
      "response-rewrite": {
        "headers": {
          "X-Response-Time": "$time_iso8601"
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

When you make requests to this route, you will see:

1. **Main request span**: `http.GET /hello` with request context
2. **Plugin execution spans**: 
   - `plugin.opentelemetry.rewrite`
   - `plugin.proxy-rewrite.rewrite` 
   - `plugin.response-rewrite.header_filter`
   - `plugin.response-rewrite.body_filter`
   - `plugin.opentelemetry.log`

Each plugin span includes:
- Plugin name and phase information
- HTTP method, URI, hostname, and user agent
- Route ID, route name, and matched path
- Service ID and service name (if available)

#### Example with Custom Span Kind

For observability providers that exclude internal spans from metrics, configure plugin spans as `server` type:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/hello",
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        },
        "trace_plugins": true,
        "plugin_span_kind": "server"
      },
      "proxy-rewrite": {
        "uri": "/get"
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

Plugin tracing is disabled by default. If you don't need plugin tracing, you can omit the `trace_plugins` attribute:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/hello",
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        },
        "trace_plugins": false
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

### Custom Span Creation API for Plugins

When the OpenTelemetry plugin is enabled with `trace_plugins: true`, other plugins can create custom spans using the `api_ctx.otel` API.

#### Basic Usage

```lua
function _M.rewrite(conf, api_ctx)
    -- Start a span (automatically nested under current plugin)
    local span_ctx = api_ctx.otel.start_span("span name")
    
    -- Your plugin logic here
    
    local success = true
    local error_msg = nil
    -- Finish the span
    api_ctx.otel.stop_span(span_ctx, success, error_msg)
end
```

#### API Functions

- **`api_ctx.otel.start_span(span_name, resource_name, kind, attributes)`**: Creates a new span
- **`api_ctx.otel.stop_span(span_ctx, success, error_msg)`**: Finishes a span

#### Parameters

- `span_name`: Name of the span (e.g., "my-plugin.operation")
- `resource_name`: Resource name (optional, currently unused)
- `kind`: Span kind - "internal", "server", "client", "producer", "consumer" (optional, defaults to "internal")
- `attributes`: Array of OpenTelemetry attribute objects (optional)
- `span_ctx`: Context returned by start_span
- `success`: Whether operation succeeded (default: true)
- `error_msg`: Error message if success is false

#### Supported Span Kinds

- **`internal`**: Internal operation within the application (default)
- **`server`**: Server-side handling of a remote request
- **`client`**: Request to a remote service where client awaits response
- **`producer`**: Initiation or scheduling of an operation (e.g., message publishing)
- **`consumer`**: Processing of an operation initiated by a producer (e.g., message consumption)

#### Examples

```lua
local attr = require("opentelemetry.attribute")

-- Simple span (default: internal)
local span_ctx = api_ctx.otel.start_span("operation-name")

-- With attributes
local span_ctx = api_ctx.otel.start_span("db-query", nil, nil, {
    attr.string("db.operation", "SELECT"),
    attr.int("user_id", 123)
})

-- With span kind
local span_ctx = api_ctx.otel.start_span("api-call", nil, "client", {
    attr.string("http.method", "GET"),
    attr.string("http.url", "https://api.example.com")
})

-- Finish span
api_ctx.otel.stop_span(span_ctx, success, error_msg)
```
