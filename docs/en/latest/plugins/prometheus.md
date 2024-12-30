---
title: prometheus
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Prometheus
description: The prometheus plugin provides the capability to integrate APISIX with Prometheus for metric collection and continuous monitoring.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/prometheus" />
</head>

## Description

The `prometheus` plugin provides the capability to integrate APISIX with [Prometheus](https://prometheus.io).

After enabling the plugin, APISIX will start collecting relevant metrics, such as API requests and latencies, and exporting them in a [text-based exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/#exposition-formats) to Prometheus. You can then create event monitoring and alerting in Prometheus to monitor the health of your API gateway and APIs.

## Attributes

There are different types of metrics in Prometheus. To understand their differences, see [metrics types](https://prometheus.io/docs/concepts/metric_types/).

The following metrics are exported by the `prometheus` plugin by default. See [get APISIX metrics](#get-apisix-metrics) for an example. Note that some metrics, such as `apisix_batch_process_entries`, are not readily visible if there are no data.


| Name                    | Type      | Description                                                                                                                                                                   |
| ------------------------------ | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| apisix_bandwidth                      | counter   | Total amount of traffic flowing through APISIX in bytes.                                                       |
| apisix_etcd_modify_indexes            | gauge     | Number of changes to etcd by APISIX keys.                                                                                                                                         |
| apisix_batch_process_entries          | gauge     | Number of remaining entries in a batch when sending data in batches, such as with `http logger`, and other logging plugins.  |
| apisix_etcd_reachable                 | gauge     | Whether APISIX can reach etcd. A value of `1` represents reachable and `0` represents unreachable.                                          |
| apisix_http_status                    | counter   | HTTP status codes returned from upstream services.                                                            |
| apisix_http_requests_total            | gauge     | Number of HTTP requests from clients.                                                                                                                                     |
| apisix_nginx_http_current_connections | gauge     | Number of current connections with clients.                                                                                   |
| apisix_nginx_metric_errors_total      | counter   | Total number of `nginx-lua-prometheus` errors.                                                                                                                                |
| apisix_http_latency                   | histogram | HTTP request latency in milliseconds.                                                                                                              |
| apisix_node_info                      | gauge     | Information of the APISIX node, such as host name.                                                                                                                                                         |
| apisix_shared_dict_capacity_bytes     | gauge     | The total capacity of an [NGINX shared dictionary](https://github.com/openresty/lua-nginx-module#ngxshareddict).                                                                                                                     |
| apisix_shared_dict_free_space_bytes   | gauge     | The remaining space in an [NGINX shared dictionary](https://github.com/openresty/lua-nginx-module#ngxshareddict).                                                                                                                   |
| apisix_upstream_status                | gauge     | Health check status of upstream nodes, available if health checks are configured on the upstream. A value of `1` represents healthy and `0` represents unhealthy.                                                                 |
| apisix_stream_connection_total        | counter   | Total number of connections handled per stream route.                                                                                                               |

## Labels

[Labels](https://prometheus.io/docs/practices/naming/#labels) are attributes of metrics that are used to differentiate metrics.

For example, the `apisix_http_status` metric can be labeled with `route` information to identify which route the HTTP status originates from.

The following are labels for a non-exhaustive list of APISIX metrics and their descriptions.

### Labels for `apisix_http_status`

The following labels are used to differentiate `apisix_http_status` metrics.

| Name   | Description                                                                                                                   |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| code         | HTTP response code returned by the upstream node.                                                                            |
| route        | ID of the route that the HTTP status originates from when `prefer_name` is `false` (default), and name of the route when `prefer_name` to `true`. Default to an empty string if a request does not match any route.                         |
| route_id     | Available only in Enterprise. ID of the route that the HTTP status originates from regardless of the `prefer_name` setting.                        |
| matched_uri  | URI of the route that matches the request. Default to an empty string if a request does not match any route.                              |
| matched_host | Host of the route that matches the request. Default to an empty string if a request does not match any route, or host is not configured on the route.                             |
| service      | ID of the service that the HTTP status originates from when `prefer_name` is `false` (default), and name of the service when `prefer_name` to `true`. Default to the configured value of host on the route if the matched route does not belong to any service. |
| service_id   | Available only in Enterprise. ID of the service that the HTTP status originates from regardless of the `prefer_name` setting. |
| consumer     | Name of the consumer associated with a request. Default to an empty string if no consumer is associated with the request.                       |
| node         | IP address of the upstream node.                                                                                          |
| gateway_group_id | Available only in Enterprise. ID of the gateway group that the HTTP status originates from. |
| instance_id | Available only in Enterprise. ID of the gateway instance that the HTTP status originates from. |
| api_product_id | Available only in Enterprise. Product ID that the HTTP status originates from. |

### Labels for `apisix_bandwidth`

The following labels are used to differentiate `apisix_bandwidth` metrics.

| Name | Description                                                                                                                   |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| type       | Type of traffic, `egress` or `ingress`.                                                                                             |
| route      | ID of the route that bandwidth corresponds to when `prefer_name` is `false` (default), and name of the route when `prefer_name` to `true`. Default to an empty string if a request does not match any route.                         |
| route_id   | Available only in Enterprise. ID of the route that bandwidth corresponds to regardless of the `prefer_name` setting.                        |
| service    | ID of the service that bandwidth corresponds to when `prefer_name` is `false` (default), and name of the service when `prefer_name` to `true`. Default to the configured value of host on the route if the matched route does not belong to any service. |
| service_id | Available only in Enterprise. ID of the service that bandwidth corresponds to regardless of the `prefer_name` setting. |
| consumer   | Name of the consumer associated with a request. Default to an empty string if no consumer is associated with the request.                       |
| node       | IP address of the upstream node.                                                                                          |
| gateway_group_id | Available only in Enterprise. ID of the gateway group that bandwidth corresponds to. |
| instance_id | Available only in Enterprise. ID of the gateway instance that bandwidth corresponds to. |
| api_product_id | Available only in Enterprise. Product ID that bandwidth corresponds to. |

### Labels for `apisix_http_latency`

The following labels are used to differentiate `apisix_http_latency` metrics.

| Name | Description                                                                                                                         |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| type       | Type of latencies. See [latency types](#latency-types) for details. |
| route      | ID of the route that latencies correspond to when `prefer_name` is `false` (default), and name of the route when `prefer_name` to `true`. Default to an empty string if a request does not match any route.                         |
| route_id   | Available only in Enterprise. ID of the route that latencies correspond to regardless of the `prefer_name` setting.                        |
| service    | ID of the service that latencies correspond to when `prefer_name` is `false` (default), and name of the service when `prefer_name` to `true`. Default to the configured value of host on the route if the matched route does not belong to any service. |
| service_id | Available only in Enterprise. ID of the service that latencies correspond to regardless of the `prefer_name` setting. |
| consumer   | Name of the consumer associated with latencies. Default to an empty string if no consumer is associated with the request.                             |
| node       | IP address of the upstream node associated with latencies.                                                                                                |
| gateway_group_id | Available only in Enterprise. ID of the gateway group that latencies correspond to. |
| instance_id | Available only in Enterprise. ID of the gateway instance that latencies correspond to. |
| api_product_id | Available only in Enterprise. Product ID that latencies correspond to. |

#### Latency Types

`apisix_http_latency` can be labeled with one of the three types:

* `request` represents the time elapsed between the first byte was read from the client and the log write after the last byte was sent to the client.

* `upstream` represents the time elapsed waiting on responses from the upstream service.

* `apisix` represents the difference between the `request` latency and `upstream` latency.

In other words, the APISIX latency is not only attributed to the Lua processing. It should be understood as follows:

```text
APISIX latency
  = downstream request time - upstream response time
  = downstream traffic latency + NGINX latency
```

### Labels for `apisix_upstream_status`

The following labels are used to differentiate `apisix_upstream_status` metrics.

| Name | Description                                                                                         |
| ---------- | --------------------------------------------------------------------------------------------------- |
| name       | Resource ID corresponding to the upstream configured with health checks, such as `/apisix/routes/1` and `/apisix/upstreams/1`. |
| ip         | IP address of the upstream node.                                                                         |
| port       | Port number of the node.                                                                            |

## Examples

The examples below demonstrate how you can work with the `prometheus` plugin for different scenarios.

### Get APISIX Metrics

The following example demonstrates how you can get metrics from APISIX.

The default Prometheus metrics endpoint and other Prometheus related configurations can be found in the [static configuration](#static-configurations). If you would like to customize these configuration, see [configuration files](/apisix/reference/configuration-files#configyaml-and-configyamlexample).

If you deploy APISIX In a containerized environment and would like to access the Prometheus metrics endpoint externally, update the configuration file as follows and [reload APISIX](/apisix/reference/apisix-cli#apisix-reload):

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    export_addr:
# highlight-next-line
      ip: 0.0.0.0 
```

Send a request to the APISIX Prometheus metrics endpoint:

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_bandwidth Total bandwidth in bytes consumed per service in Apisix
# TYPE apisix_bandwidth counter
apisix_bandwidth{type="egress",route="",service="",consumer="",node=""} 8417
apisix_bandwidth{type="egress",route="1",service="",consumer="",node="127.0.0.1"} 1420
apisix_bandwidth{type="egress",route="2",service="",consumer="",node="127.0.0.1"} 1420
apisix_bandwidth{type="ingress",route="",service="",consumer="",node=""} 189
apisix_bandwidth{type="ingress",route="1",service="",consumer="",node="127.0.0.1"} 332
apisix_bandwidth{type="ingress",route="2",service="",consumer="",node="127.0.0.1"} 332
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 0
...
```

### Expose APISIX Metrics on Public API Endpoint

The following example demonstrates how you can disable the Prometheus export server that, by default, exposes an endpoint on port `9091`, and expose APISIX Prometheus metrics on a new public API endpoint on port `9080`, which APISIX uses to listen to other client requests.

:::caution

If a large quantity of metrics are being collected, the plugin could take up a significant amount of CPU resources for metric computations and negatively impact the processing of regular requests.

To address this issue, APISIX uses [privileged agent](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) and offloads the metric computations to a separate process. This optimization applies automatically if you use the metric endpoint configured in the configuration files, as demonstrated [above](#get-apisix-metrics). If you expose the metric endpoint with the `public-api` plugin, you will not benefit from this optimization.

:::

Disable the Prometheus export server in the configuration file and [reload APISIX](/apisix/reference/apisix-cli#apisix-reload) for changes to take effect:

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

Next, create a route with [`public-api`](/hub/public-api) plugin and expose a public API endpoint for APISIX metrics:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/prometheus-metrics" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/apisix/prometheus/metrics",
    "plugins": {
      "public-api": {}
    }
  }'
```

Send a request to the new metrics endpoint to verify:

```shell
curl "http://127.0.0.1:9080/apisix/prometheus/metrics"
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

### Integrate APISIX with Prometheus and Grafana

To learn about how to collect APISIX metrics with Prometheus and visualize them in Grafana, see [how-to guide](/apisix/how-to-guide/observability/monitor-apisix-with-prometheus).

### Monitor Upstream Health Statuses

The following example demonstrates how to monitor the health status of upstream nodes.

Create a route with the `prometheus` plugin and configure upstream active health checks:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "prometheus-route",
    "uri": "/get",
    "plugins": {
      "prometheus": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1,
        "127.0.0.1:20001": 1
      },
      "checks": {
        "active": {
          "timeout": 5,
          "http_path": "/status",
          "healthy": {
            "interval": 2,
            "successes": 1
          },
          "unhealthy": {
            "interval": 1,
            "http_failures": 2
          }
        },
        "passive": {
          "healthy": {
            "http_statuses": [200, 201],
            "successes": 3
          },
          "unhealthy": {
            "http_statuses": [500],
            "http_failures": 3,
            "tcp_failures": 3
          }
        }
      }
    }
  }'
```

Send a request to the APISIX Prometheus metrics endpoint:

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_upstream_status upstream status from health check
# TYPE apisix_upstream_status gauge
apisix_upstream_status{name="/apisix/routes/1",ip="54.237.103.220",port="80"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="20001"} 0
```

This shows that the upstream node `httpbin.org:80` is healthy and the upstream node `127.0.0.1:20001` is unhealthy.

To learn more about how to configure active and passive health checks, see [health checks](/apisix/how-to-guide/traffic-management/health-check).

### Add Extra Labels for Metrics

The following example demonstrates how to add additional labels to metrics and use [built-in variables](/apisix/reference/built-in-variables) in label values.

Currently, only the following metrics support extra labels:

* apisix_http_status
* apisix_http_latency
* apisix_bandwidth

Include the following configurations in the [configuration file](/apisix/reference/configuration-files#configyaml-and-configyamlexample) to add labels for metrics and [reload APISIX](/apisix/reference/apisix-cli#apisix-reload) for changes to take effect:

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:                                # Plugin: prometheus
    metrics:                                 # Create extra labels from built-in variables.
      http_status:
        extra_labels:                        # Set the extra labels for http_status metrics.
          - upstream_addr: $upstream_addr    # Add an extra upstream_addr label with value being the NGINX variable $upstream_addr.
          - route_name: $route_name          # Add an extra route_name label with value being the APISIX variable $route_name.
```

Note that if you define a variable in the label value but it does not correspond to any existing  [built-in variables](/apisix/reference/built-in-variables), the label value will default to an empty string.

Create a route with the `prometheus` plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "prometheus-route",
    "uri": "/get",
    "name": "extra-label",
    "plugins": {
      "prometheus": {}
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to the route to verify:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

Send a request to the APISIX Prometheus metrics endpoint:

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_http_status HTTP status codes per service in APISIX
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="1",matched_uri="/get",matched_host="",service="",consumer="",node="54.237.103.220",upstream_addr="54.237.103.220:80",route_name="extra-label"} 1
```

### Monitor TCP/UDP Traffic with Prometheus

The following example demonstrates how to collect TCP/UDP traffic metrics in APISIX.

Include the following configurations in the [configuration file](/apisix/reference/configuration-files#configyaml-and-configyamlexample) to enable stream proxy and `prometheus` plugin for stream proxy. [Reload APISIX](/apisix/reference/apisix-cli#apisix-reload) for changes to take effect:

```yaml title="conf/config.yaml"
apisix:
  proxy_mode: http&stream   # Enable both L4 & L7 proxies
  stream_proxy:             # Configure L4 proxy
    tcp:
      - 9100                # Set TCP proxy listening port
    udp:
      - 9200                # Set UDP proxy listening port

stream_plugins:
  - prometheus              # Enable prometheus for stream proxy
```

Create a [stream route](/apisix/key-concepts/stream-routes) with the `prometheus` plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "prometheus-route",
    "plugins": {
      "prometheus":{}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to the stream route to verify:

```shell
curl -i "http://127.0.0.1:9100"
```

You should see an `HTTP/1.1 200 OK` response.

Send a request to the APISIX Prometheus metrics endpoint:

```shell
curl "http://127.0.0.1:9091/apisix/prometheus/metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_stream_connection_total Total number of connections handled per stream route in APISIX
# TYPE apisix_stream_connection_total counter
apisix_stream_connection_total{route="1"} 1
```
