---
title: toolset
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Toolset
  - toolset
  - trace
  - table-count
description: This document contains information about the Apache APISIX toolset Plugin.
---

<head>
    <link rel="canonical" href="https://docs.api7.ai/hub/toolset" />
</head>

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

The `toolset` Plugin is a diagnostics and observability framework that hosts multiple lightweight sub-plugins. Sub-plugins are configured by editing `apisix/plugins/toolset/config.lua` and are dynamically loaded or unloaded at runtime — the plugin checks for configuration changes every second without requiring an APISIX restart. The `toolset` plugin itself has no per-route schema and always operates at the global scope.

### Sub-plugins

| Sub-plugin    | Description                                                                                    |
|---------------|------------------------------------------------------------------------------------------------|
| `trace`       | Instruments APISIX request phases and emits a timing table to the error log for matching requests. |
| `table_count` | Periodically measures and logs the item count of specified Lua module tables.                   |

## Attributes

Sub-plugin configuration is managed through `apisix/plugins/toolset/config.lua`. The file returns a Lua table with per-sub-plugin keys. The plugin reloads this file automatically every second, so changes take effect without restarting APISIX.

### trace

| Name                  | Type    | Required | Default | Description                                                                                                  |
|-----------------------|---------|----------|---------|--------------------------------------------------------------------------------------------------------------|
| rate                  | integer | False    | 1       | Sampling rate as N-out-of-100. `1` traces 1 request per 100; set to `100` to trace every request.           |
| hosts                 | array   | False    | `[]`    | Allowlist of `Host` header values (glob patterns supported). Empty means all hosts pass.                      |
| paths                 | array   | False    | `[]`    | Allowlist of request URI patterns (glob patterns supported). Empty means all paths pass.                      |
| gen_uid               | boolean | False    | false   | When `true`, generates a UUID for traces where no standard trace header (`x-request-id`, `traceparent`, etc.) is found. |
| vars                  | array   | False    | `[]`    | Additional nginx or APISIX variables to prepend to the trace output.                                         |
| timespan_threshold    | number  | False    | 0       | Minimum total request duration (in seconds) required before emitting the trace log. `0` logs all traces.    |

### table_count

| Name         | Type    | Required | Default                           | Description                                                                           |
|--------------|---------|----------|-----------------------------------|---------------------------------------------------------------------------------------|
| lua_modules  | array   | True     |                                   | List of Lua module paths to measure (e.g. `["apisix.router"]`).                       |
| interval     | integer | False    | 5                                 | Interval in seconds between measurements.                                              |
| depth        | integer | False    | 10                                | Maximum recursion depth when counting table entries. `0` disables recursive counting. |
| scopes       | array   | False    | `["worker", "privileged agent"]`  | APISIX process types in which the sub-plugin runs.                                    |

## Enable Plugin

Add `toolset` to the `plugins` list in `config.yaml`:

```yaml
plugins:
  - toolset
```

Then configure sub-plugins by editing `apisix/plugins/toolset/config.lua`. The default file ships with all sub-plugins disabled (empty `lua_modules`, etc.). Edit it to activate:

```lua
return {
  trace = {
    rate = 10,
    hosts = { "*.example.com" },
    paths = { "/api/*" },
    gen_uid = true,
    vars = { "remote_addr" },
    timespan_threshold = 0.5
  },
  table_count = {
    lua_modules = { "apisix.router" },
    interval = 10,
    depth = 5,
    scopes = { "worker" }
  }
}
```

Changes to `config.lua` are detected and applied within one second — no restart required.

## Example usage

### Tracing slow requests

The following configuration in `apisix/plugins/toolset/config.lua` traces up to 10% of requests to `*.example.com` whose total processing time exceeds 500ms:

```lua
return {
  trace = {
    rate = 10,
    hosts = { "*.example.com" },
    timespan_threshold = 0.5
  }
}
```

When a request meets the criteria, APISIX writes a table similar to the following to the error log at `WARN` level:

```
+----------+---------------------------+----------+-------------------------+
| Role     | Phase                     | Timespan | Start time              |
+----------+---------------------------+----------+-------------------------+
| APISIX   | access                    | 3ms      | 2024-01-01 12:00:00.123 |
| APISIX   | \_match_route             | 1ms      | 2024-01-01 12:00:00.124 |
| APISIX   | balancer                  | 1ms      | 2024-01-01 12:00:00.125 |
| Upstream | upstream (req + response) | 520ms    | 2024-01-01 12:00:00.126 |
| APISIX   | header_filter             | 0ms      | 2024-01-01 12:00:00.646 |
| APISIX   | body_filter               | 0ms      | 2024-01-01 12:00:00.646 |
| Client   | response                  | 1ms      | 2024-01-01 12:00:00.647 |
| APISIX   | log                       | 0ms      | 2024-01-01 12:00:00.648 |
+----------+---------------------------+----------+-------------------------+
```

### Monitoring router table growth

The following configuration in `apisix/plugins/toolset/config.lua` measures the item count of the `apisix.router` Lua module every 30 seconds in worker processes:

```lua
return {
  table_count = {
    lua_modules = { "apisix.router" },
    interval = 30,
    depth = 5,
    scopes = { "worker" }
  }
}
```

Results are written to the error log at `WARN` level:

```
package apisix.router table count is: 1234 for loaded: 1
```

## Disable Plugin

Remove the sub-plugin configuration from `apisix/plugins/toolset/config.lua` (set `lua_modules` to `{}` or remove `trace`), or remove `toolset` from the `plugins` list in `config.yaml` and reload APISIX:

```yaml
plugins:
  # - toolset   # remove or comment out
```
