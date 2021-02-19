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

- [中文](../zh-cn/plugins/prometheus.md)

# prometheus

This plugin exposes metrics in Prometheus Exposition format.

## Attributes

none.

## API

This plugin will add `/apisix/prometheus/metrics` to expose the metrics.
You may need to use [interceptors](../plugin-interceptors.md) to protect it.

## How to enable it

`prometheus` plugin can be enable with empty table, because it doesn't have
any options yet.

For example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "prometheus":{}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:

![](../images/plugin/prometheus-1.png)

Then add prometheus plugin:

![](../images/plugin/prometheus-2.png)

## How to fetch the metric data

We fetch the metric data from the specified url `/apisix/prometheus/metrics`.

```
curl -i http://127.0.0.1:9080/apisix/prometheus/metrics
```

Puts this URL address into prometheus, and it will automatically fetch
these metric data.

For example like this:

```yaml
scrape_configs:
  - job_name: 'apisix'
    metrics_path: '/apisix/prometheus/metrics'
    static_configs:
    - targets: ['127.0.0.1:9080']
```

And we can check the status at prometheus console:

![](../../doc/images/plugin/prometheus01.png)

![](../../doc/images/plugin/prometheus02.png)

## How to specify export uri

We can change the default export uri in the `plugin_attr` section of `conf/config.yaml`.

| Name       | Type   | Default                      | Description                       |
| ---------- | ------ | ---------------------------- | --------------------------------- |
| export_uri | string | "/apisix/prometheus/metrics" | uri to get the prometheus metrics |

Here is an example:

```yaml
plugin_attr:
  prometheus:
    export_uri: /apisix/metrics
```

### Grafana dashboard

Metrics exported by the plugin can be graphed in Grafana using a drop in dashboard.

Downloads [Grafana dashboard meta](../json/apisix-grafana-dashboard.json) and imports it to Grafana。

Or you can goto [Grafana official](https://grafana.com/grafana/dashboards/11719) for `Grafana` meta data.

![](../../doc/images/plugin/grafana_1.png)

![](../../doc/images/plugin/grafana_2.png)

![](../../doc/images/plugin/grafana_3.png)

### Available metrics

* `Status codes`: HTTP status codes returned by upstream services. These are available per service and across all services.
* `Bandwidth`: Total Bandwidth (egress/ingress) flowing through apisix. This metric is available per service and as a sum across all services.
* `etcd reachability`: A gauge type with a value of 0 or 1, representing if etcd can be reached by a apisix or not.
* `Connections`: Various Nginx connection metrics like active, reading, writing, and number of accepted connections.
* `Batch process entries`: A gauge type, when we use plugins and the plugin used batch process to send data, such as: sys logger, http logger, sls logger, tcp logger, udp logger and zipkin, then the entries which hasn't been sent in batch process will be counted in the metrics.
* `Latency`: The per service histogram of request time and the overhead added by APISIX (request time - upstream response time).
* `Info`: the information of APISIX node.

Here is the original metric data of apisix:

```
$ curl http://127.0.0.1:9080/apisix/prometheus/metrics
# HELP apisix_bandwidth Total bandwidth in bytes consumed per service in Apisix
# TYPE apisix_bandwidth counter
apisix_bandwidth{type="egress",service="127.0.0.2"} 183
apisix_bandwidth{type="egress",service="bar.com"} 183
apisix_bandwidth{type="egress",service="foo.com"} 2379
apisix_bandwidth{type="ingress",service="127.0.0.2"} 83
apisix_bandwidth{type="ingress",service="bar.com"} 76
apisix_bandwidth{type="ingress",service="foo.com"} 988
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 0
apisix_etcd_modify_indexes{key="max_modify_index"} 222
apisix_etcd_modify_indexes{key="prev_index"} 35
apisix_etcd_modify_indexes{key="protos"} 0
apisix_etcd_modify_indexes{key="routes"} 222
apisix_etcd_modify_indexes{key="services"} 0
apisix_etcd_modify_indexes{key="ssls"} 0
apisix_etcd_modify_indexes{key="stream_routes"} 0
apisix_etcd_modify_indexes{key="upstreams"} 0
apisix_etcd_modify_indexes{key="x_etcd_index"} 223
# HELP apisix_batch_process_entries batch process remaining entries
# TYPE apisix_batch_process_entries gauge
apisix_batch_process_entries{name="http-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="sls-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="tcp-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="udp-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="sys-logger",route_id="9",server_addr="127.0.0.1"} 1
apisix_batch_process_entries{name="zipkin_report",route_id="9",server_addr="127.0.0.1"} 1
# HELP apisix_etcd_reachable Config server etcd reachable from Apisix, 0 is unreachable
# TYPE apisix_etcd_reachable gauge
apisix_etcd_reachable 1
# HELP apisix_http_status HTTP status codes per service in Apisix
# TYPE apisix_http_status counter
apisix_http_status{code="200",service="127.0.0.2"} 1
apisix_http_status{code="200",service="bar.com"} 1
apisix_http_status{code="200",service="foo.com"} 13
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 11994
apisix_nginx_http_current_connections{state="active"} 2
apisix_nginx_http_current_connections{state="handled"} 11994
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="total"} 1191780
apisix_nginx_http_current_connections{state="waiting"} 1
apisix_nginx_http_current_connections{state="writing"} 1
# HELP apisix_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE apisix_nginx_metric_errors_total counter
apisix_nginx_metric_errors_total 0
# HELP apisix_http_latency HTTP request latency in milliseconds per service in APISIX
# TYPE apisix_http_latency histogram
apisix_http_latency_bucket{type="request",service="",consumer="",node="127.0.0.1",le="00001.0"} 1
apisix_http_latency_bucket{type="request",service="",consumer="",node="127.0.0.1",le="00002.0"} 1
...
# HELP apisix_http_overhead HTTP request overhead added by APISIX in milliseconds per service in APISIX
# TYPE apisix_http_overhead histogram
apisix_http_overhead_bucket{type="request",service="",consumer="",node="127.0.0.1",le="00001.0"} 1
apisix_http_overhead_bucket{type="request",service="",consumer="",node="127.0.0.1",le="00002.0"} 1
...
# HELP apisix_node_info Info of APISIX node
# TYPE apisix_node_info gauge
apisix_node_info{hostname="desktop-2022q8f-wsl"} 1
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable `prometheus`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
