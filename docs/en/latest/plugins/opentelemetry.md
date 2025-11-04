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
| trace_plugins                        | object        | False    | `{"enabled": false, "plugin_span_kind": "internal", "excluded_plugins": ["opentelemetry", "prometheus"]}` | -            | Configuration for plugin execution tracing. |
| trace_plugins.enabled                 | boolean       | False    | `false`      | -            | Whether to trace individual plugin execution phases. When enabled, creates child spans for each plugin phase (rewrite, access, header_filter, body_filter, log) with comprehensive request context attributes. |
| trace_plugins.plugin_span_kind       | string        | False    | `internal`   | ["internal", "server"] | Span kind for plugin execution spans. Some observability providers may exclude internal spans from metrics and dashboards. Use 'server' if you need plugin spans included in service-level metrics. |
| trace_plugins.excluded_plugins       | array[string] | False    | `["opentelemetry", "prometheus"]` | -            | List of plugin names to exclude from tracing. Useful for excluding plugins like `opentelemetry` or `prometheus` that may add unnecessary overhead when traced. |

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

The `trace_plugins` object allows you to trace individual plugin execution phases. When enabled (`trace_plugins.enabled: true`), the OpenTelemetry plugin creates child spans for each plugin phase (rewrite, access, header_filter, body_filter, log) with comprehensive request context attributes.

**Note**: Plugin tracing is **disabled by default** (`trace_plugins.enabled: false`). You must explicitly enable it to see plugin execution spans.

#### Configuration Options

The `trace_plugins` object supports the following properties:

- **`enabled`** (boolean, default: `false`): Whether to trace plugin execution phases.
- **`plugin_span_kind`** (string, default: `"internal"`): Span kind for plugin execution spans. Use `"server"` if your observability provider excludes internal spans from metrics.
- **`excluded_plugins`** (array of strings, default: `["opentelemetry", "prometheus"]`): List of plugin names to exclude from tracing.

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
        "trace_plugins": {
          "enabled": true
        }
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
2. **Plugin execution spans**

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
        "trace_plugins": {
          "enabled": true,
          "plugin_span_kind": "server"
        }
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

Plugin tracing is disabled by default. If you don't need plugin tracing, you can omit the `trace_plugins` attribute or set `enabled: false`:

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
        "trace_plugins": {
          "enabled": false
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

#### Excluding Specific Plugins from Tracing

You can exclude specific plugins from tracing using the `excluded_plugins` option. This is useful for plugins like `opentelemetry` or `prometheus` that may add unnecessary overhead when traced:

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
        "trace_plugins": {
          "enabled": true,
          "excluded_plugins": ["opentelemetry", "prometheus", "proxy-rewrite"]
        }
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

### Custom Span Creation API for Plugins

When the OpenTelemetry plugin is enabled with `trace_plugins.enabled: true`, other plugins can create custom spans using the `api_ctx.otel` API.

#### API Functions

- **`api_ctx.otel.start_span(span_info)`**: Creates a new span with simplified parent context resolution
- **`api_ctx.otel.stop_span(span_ctx, error_msg)`**: Finishes a span (error_msg sets error status if provided)
- **`api_ctx.otel.current_span()`**: Gets the current span context (most recently started span)
- **`api_ctx.otel.get_plugin_context(plugin_name, phase)`**: Gets the span context for a specific plugin phase
- **`api_ctx.otel.with_span(span_info, fn)`**: Creates a span, executes a function, and automatically finishes the span with error handling

#### Parameters

- `span_info`: Object containing span configuration
  - `name`: Name of the span (required)
  - `kind`: Span kind constant (optional, defaults to span_kind.internal)
  - `parent`: Parent span context (optional, defaults to current plugin phase span or main request context)
  - `attributes`: Array of OpenTelemetry attribute objects (optional)
- `span_ctx`: Context returned by start_span
- `error_msg`: Error message (optional, if provided sets span status to ERROR)
- `plugin_name`: Name of the plugin (required for get_plugin_context)
- `phase`: Plugin phase name (required for get_plugin_context): `"rewrite"`, `"access"`, `"header_filter"`, `"body_filter"`, or `"log"`
- `fn`: Function to execute within the span (required for with_span). The function receives `span_ctx` as its first parameter, allowing you to access the span and set attributes using `span_ctx:span():set_attributes(...)`

#### Supported Span Kinds

Use OpenTelemetry span kind constants directly:

```lua
local span_kind = require("opentelemetry.trace.span_kind")

-- Available span kinds:
span_kind.internal  -- Internal operation (default)
span_kind.server    -- Server-side handling of a remote request
span_kind.client    -- Request to a remote service
span_kind.producer  -- Initiation of an operation (e.g., message publishing)
span_kind.consumer  -- Processing of an operation (e.g., message consumption)
```

#### Examples

```lua
local attr = require("opentelemetry.attribute")
local span_kind = require("opentelemetry.trace.span_kind")

-- Simple span (default: internal, nested under current plugin phase)
local span_ctx = api_ctx.otel.start_span({
    name = "operation-name"
})

-- With attributes and resource
local span_ctx = api_ctx.otel.start_span({
    name = "db-query",
    resource = "database",
    attributes = {
        attr.string("db.operation", "SELECT"),
        attr.int("user_id", 123)
    }
})

-- With span kind
local span_ctx = api_ctx.otel.start_span({
    name = "api-call",
    resource = "external-api",
    kind = span_kind.client,
    attributes = {
        attr.string("http.method", "GET"),
        attr.string("http.url", "https://api.example.com")
    }
})

-- With custom parent context (get plugin phase context)
local parent_ctx = api_ctx.otel.get_plugin_context("some-plugin", "rewrite")
local span_ctx = api_ctx.otel.start_span({
    name = "child-operation",
    parent = parent_ctx,
    kind = span_kind.internal
})

-- Or use current span as parent
local current_ctx = api_ctx.otel.current_span()
if current_ctx then
    local span_ctx = api_ctx.otel.start_span({
        name = "child-operation",
        parent = current_ctx,
        kind = span_kind.internal
    })
end

-- Finish span (success)
api_ctx.otel.stop_span(api_ctx.otel.current_span())

-- Finish span with error
api_ctx.otel.stop_span(api_ctx.otel.current_span(), "operation failed")
```

#### Using `with_span` for Automatic Span Management

The `with_span` function is a convenience method that automatically creates a span, executes your function, and finishes the span with proper error handling.

**Function Signature:**

```lua
err, ...values = api_ctx.otel.with_span(span_info, fn)
```

The function `fn` receives the `span_ctx` as its first parameter, allowing you to access the span and set attributes during execution:

```lua
function(span_ctx)
    -- Access the span and set attributes
    local span = span_ctx:span()
    span:set_attributes(attr.string("key", "value"))
    -- Your code here
    return nil, "foo"
end
```

**Behavior:**

- Creates a span based on `span_info`
- Executes the function `fn` with error protection, passing `span_ctx` as the first parameter
- Automatically finishes the span after execution
- Sets span status to ERROR if the function throws a Lua error or returns an error
- Returns function results in error-first pattern (err, ...values)

**Examples:**

```lua
local attr = require("opentelemetry.attribute")
local span_kind = require("opentelemetry.trace.span_kind")

-- Simple usage
local err, result = api_ctx.otel.with_span({
    name = "my-operation"
}, function(span_ctx)
    return nil, "foo"
end)
-- err is nil, result is "foo"

-- Setting attributes during execution
local err, result = api_ctx.otel.with_span({
    name = "my-operation"
}, function(span_ctx)
    local span = span_ctx:span()
    span:set_attributes(
        attr.string("operation.type", "example"),
        attr.int("items.processed", 42)
    )
    return nil, "foo"
end)

-- With span kind
local err, result = api_ctx.otel.with_span({
    name = "my-operation",
    kind = span_kind.client
}, function(span_ctx)
    return nil, "foo"
end)
```

#### Advanced Usage

The API supports creating spans with custom parent contexts and rich attributes:

```lua
-- Get context from another plugin phase
local auth_ctx = api_ctx.otel.get_plugin_context("auth-plugin", "access")
if auth_ctx then
    local span_ctx = api_ctx.otel.start_span({
        name = "auth-verification",
        parent = auth_ctx,
        kind = span_kind.internal,
        attributes = {
            attr.string("auth.method", "jwt"),
            attr.string("user.id", user_id)
        }
    })

    -- Perform authentication logic
    local success = verify_token(token)

    -- Finish with appropriate status
    api_ctx.otel.stop_span(span_ctx, success and nil or "authentication failed")
end
```
