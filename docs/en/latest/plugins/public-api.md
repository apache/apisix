---
title: public-api
keywords:
  - Apache APISIX
  - API Gateway
  - Public API
description: The `public-api` plugin exposes an internal API endpoint, making it publicly accessible. One of the primary use cases of this plugin is to expose internal endpoints created by other plugins.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/public-api" />
</head>

## Description

The `public-api` plugin exposes an internal API endpoint, making it publicly accessible. One of the primary use cases of this plugin is to expose internal endpoints created by other plugins.

## Attributes

| Name    | Type      | Required | Default | Valid Values | Description |
|---------|-----------|----------|---------|--------------|-------------|
| uri     | string    | False    | -       | -            | Internal endpoint to expose. If not configured, expose the route URI. |

## Example

### Expose Prometheus Metrics at Custom Endpoint

The following example demonstrates how you can disable the Prometheus export server that, by default, exposes an endpoint on port `9091`, and expose APISIX Prometheus metrics on a new public API endpoint on port `9080`, which APISIX uses to listen to other client requests.

You will also configure the route such that the internal endpoint `/apisix/prometheus/metrics` is exposed at a custom endpoint.

:::caution

If a large quantity of metrics is being collected, the plugin could take up a significant amount of CPU resources for metric computations and negatively impact the processing of regular requests.

To address this issue, APISIX uses [privileged agent](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) and offloads the metric computations to a separate process. This optimization applies automatically if you use the metric endpoint configured under `plugin_attr.prometheus.export_addr` in the configuration file. If you expose the metric endpoint with the `public-api` plugin, you will not benefit from this optimization.

:::

Disable the Prometheus export server in the configuration file and reload APISIX for changes to take effect:

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

Next, create a route with the `public-api` plugin and expose a public API endpoint for APISIX metrics. You should set the route `uri` to the custom endpoint path and set the plugin `uri` to the internal endpoint to be exposed.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/prometheus-metrics" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/prometheus_metrics",
    "plugins": {
      "public-api": {
        "uri": "/apisix/prometheus/metrics"
      }
    }
  }'
```

Send a request to the custom metrics endpoint:

```shell
curl "http://127.0.0.1:9080/prometheus_metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_http_requests_total The total number of client requests since APISIX started
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 1
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 1
apisix_nginx_http_current_connections{state="active"} 1
apisix_nginx_http_current_connections{state="handled"} 1
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 0
apisix_nginx_http_current_connections{state="writing"} 1
...
```
