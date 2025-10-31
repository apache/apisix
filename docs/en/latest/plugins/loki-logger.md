---
title: loki-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Loki-logger
  - Grafana Loki
description: The loki-logger Plugin pushes request and response logs in batches to Grafana Loki, via the Loki HTTP API /loki/api/v1/push. The Plugin also supports the customization of log formats.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/loki-logger" />
</head>

## Description

The `loki-logger` Plugin pushes request and response logs in batches to [Grafana Loki](https://grafana.com/oss/loki/), via the [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/#loki-http-api) `/loki/api/v1/push`. The Plugin also supports the customization of log formats.

When enabled, the Plugin will serialize the request context information to [JSON objects](https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki) and add them to the queue, before they are pushed to Loki. See [batch processor](../batch-processor.md) for more details.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|---|---|---|---|---|---|
| endpoint_addrs | array[string] | True |  | | Loki API base URLs, such as `http://127.0.0.1:3100`. If multiple endpoints are configured, the log will be pushed to a randomly determined endpoint from the list. |
| endpoint_uri | string | False | /loki/api/v1/push | | URI path to the Loki ingest endpoint. |
| tenant_id | string | False | fake | | Loki tenant ID. According to Loki's [multi-tenancy documentation](https://grafana.com/docs/loki/latest/operations/multi-tenancy/#multi-tenancy), the default value is set to `fake` under single-tenancy. |
| headers | object | False |  |  | Key-value pairs of request headers (settings for `X-Scope-OrgID` and `Content-Type` will be ignored). |
| log_labels | object | False | {job = "apisix"} | | Loki log label. Support [NGINX variables](https://nginx.org/en/docs/varindex.html) and constant strings in values. Variables should be prefixed with a `$` sign. For example, the label can be `{"origin" = "apisix"}` or `{"origin" = "$remote_addr"}`. |
| ssl_verify        | boolean       | False    | true | | If true, verify Loki's SSL certificates. |
| timeout           | integer       | False    | 3000 | [1, 60000] | Timeout for the Loki service HTTP call in milliseconds.  |
| keepalive         | boolean       | False    | true |  | If true, keep the connection alive for multiple requests. |
| keepalive_timeout | integer       | False    | 60000 | >=1000 | Keepalive timeout in milliseconds.  |
| keepalive_pool    | integer       | False    | 5       | >=1 | Maximum number of connections in the connection pool.  |
| log_format | object | False    |          | | Custom log format as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX variables](../apisix-variable.md) and [NGINX variables](http://nginx.org/en/docs/varindex.html) can be referenced by prefixing with `$`. |
| name | string | False    | loki-logger | | Unique identifier of the Plugin for the batch processor. If you use [Prometheus](./prometheus.md) to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`. |
| include_req_body       | boolean | False    | false | | If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it can not be logged due to NGINX's limitations. |
| include_req_body_expr  | array[array]   | False    |  | | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_req_body` is true. Request body would only be logged when the expressions configured here evaluate to true. |
| include_resp_body      | boolean | False    | false | | If true, include the response body in the log.  |
| include_resp_body_expr | array[array]   | False    |  | | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_resp_body` is true. Response body would only be logged when the expressions configured here evaluate to true. |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Plugin Metadata

You can also configure log format on a global scale using the [Plugin Metadata](../terminology/plugin-metadata.md), which configures the log format for all `loki-logger` Plugin instances. If the log format configured on the individual Plugin instance differs from the log format configured on Plugin metadata, the log format configured on the individual Plugin instance takes precedence.

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| log_format | object | False |  | Custom log format as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX variables](../apisix-variable.md) and [NGINX variables](http://nginx.org/en/docs/varindex.html) can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

## Examples

The examples below demonstrate how you can configure `loki-logger` Plugin for different scenarios.

To follow along the examples, start a sample Loki instance in Docker:

```shell
wget https://raw.githubusercontent.com/grafana/loki/v3.0.0/cmd/loki/loki-local-config.yaml -O loki-config.yaml
docker run --name loki -d -v $(pwd):/mnt/config -p 3100:3100 grafana/loki:3.2.1 -config.file=/mnt/config/loki-config.yaml
```

Additionally, start a Grafana instance to view and visualize the logs:

```shell
docker run -d --name=apisix-quickstart-grafana \
  -p 3000:3000 \
  grafana/grafana-oss
```

To connect Loki and Grafana, visit Grafana at [`http://localhost:3000`](http://localhost:3000). Under __Connections > Data sources__, add a new data source and select Loki. Your connection URL should follow the format of `http://{your_ip_address}:3100`. When saving the new data source, Grafana should also test the connection, and you are expected to see Grafana notifying the data source is successfully connected.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log Requests and Responses in Default Log Format

The following example demonstrates how you can configure the `loki-logger` Plugin on a Route to log requests and responses going through the route.

Create a Route with the `loki-logger` Plugin and configure the address of Loki:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send a few requests to the Route to generate log entries:

```shell
curl "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses for all requests.

Navigate to the [Grafana explore view](http://localhost:3000/explore) and run a query `job = apisix`. You should see a number of logs corresponding to your requests, such as the following:

```json
{
  "route_id": "loki-logger-route",
  "response": {
    "status": 200,
    "headers": {
      "date": "Fri, 03 Jan 2025 03:54:26 GMT",
      "server": "APISIX/3.11.0",
      "access-control-allow-credentials": "true",
      "content-length": "391",
      "access-control-allow-origin": "*",
      "content-type": "application/json",
      "connection": "close"
    },
    "size": 619
  },
  "start_time": 1735876466,
  "client_ip": "192.168.65.1",
  "service_id": "",
  "apisix_latency": 5.0000038146973,
  "upstream": "34.197.122.172:80",
  "upstream_latency": 666,
  "server": {
    "hostname": "0b9a772e68f8",
    "version": "3.11.0"
  },
  "request": {
    "headers": {
      "user-agent": "curl/8.6.0",
      "accept": "*/*",
      "host": "127.0.0.1:9080"
    },
    "size": 85,
    "method": "GET",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "uri": "/anything"
  },
  "latency": 671.0000038147
}
```

This verifies that Loki has been receiving logs from APISIX. You may also create dashboards in Grafana to further visualize and analyze the logs.

### Customize Log Format with Plugin Metadata

The following example demonstrates how you can customize log format using [Plugin Metadata](../terminology/plugin-metadata.md).

Create a Route with the `loki-logger` plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"]
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

Configure Plugin metadata for `loki-logger`, which will update the log format for all routes of which requests would be logged:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/loki-logger" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "log_format": {
      "host": "$host",
      "client_ip": "$remote_addr",
      "route_id": "$route_id",
      "@timestamp": "$time_iso8601"
    }
  }'
```

Send a request to the Route to generate a new log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to the [Grafana explore view](http://localhost:3000/explore) and run a query `job = apisix`. You should see a log entry corresponding to your request, similar to the following:

```json
{
  "@timestamp":"2025-01-03T21:11:34+00:00",
  "client_ip":"192.168.65.1",
  "route_id":"loki-logger-route",
  "host":"127.0.0.1"
}
```

If the Plugin on a Route specifies a specific log format, it will take precedence over the log format specified in the Plugin metadata. For instance, update the Plugin on the previous Route as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/loki-logger-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "loki-logger": {
        "log_format": {
          "route_id": "$route_id",
          "client_ip": "$remote_addr",
          "@timestamp": "$time_iso8601"
        }
      }
    }
  }'
```

Send a request to the Route to generate a new log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to the [Grafana explore view](http://localhost:3000/explore) and re-run the query `job = apisix`. You should see a log entry corresponding to your request, consistent with the format configured on the route, similar to the following:

```json
{
  "client_ip":"192.168.65.1",
  "route_id":"loki-logger-route",
  "@timestamp":"2025-01-03T21:19:45+00:00"
}
```

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with `loki-logger` to only log request body if the URL query string `log_body` is `yes`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"],
        "include_req_body": true,
        "include_req_body_expr": [["arg_log_body", "==", "yes"]]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send a request to the Route with a URL query string satisfying the condition:

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

Navigate to the [Grafana explore view](http://localhost:3000/explore) and run the query `job = apisix`. You should see a log entry corresponding to your request, where the request body is logged:

```json
{
  "route_id": "loki-logger-route",
  ...,
  "request": {
    "headers": {
      ...
    },
    "body": "{\"env\": \"dev\"}",
    "size": 182,
    "method": "POST",
    "url": "http://127.0.0.1:9080/anything?log_body=yes",
    "querystring": {
      "log_body": "yes"
    },
    "uri": "/anything?log_body=yes"
  },
  "latency": 809.99994277954
}
```

Send a request to the Route without any URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

Navigate to the [Grafana explore view](http://localhost:3000/explore) and run the query `job = apisix`. You should see a log entry corresponding to your request, where the request body is not logged:

```json
{
  "route_id": "loki-logger-route",
  ...,
  "request": {
    "headers": {
      ...
    },
    "size": 169,
    "method": "POST",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "uri": "/anything"
  },
  "latency": 557.00016021729
}
```

:::info

If you have customized the `log_format` in addition to setting `include_req_body` or `include_resp_body` to `true`, the Plugin would not include the bodies in the logs.

As a workaround, you may be able to use the NGINX variable `$request_body` in the log format, such as:

```json
{
  "kafka-logger": {
    ...,
    "log_format": {"body": "$request_body"}
  }
}
```

:::

## FAQ

### Logs are not pushed properly

Look at `error.log` for such a log.

```text
2023/04/30 13:45:46 [error] 19381#19381: *1075673 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 401, body: no org id, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
```

The error can be diagnosed based on the error code in the `failed to process entries: loki server returned status: 401, body: no org id` and the response body of the loki server.

### Getting errors when RPS is high?

- Make sure to `keepalive` related configuration is set properly. See [Attributes](#attributes) for more information.
- Check the logs in `error.log`, look for such a log.

    ```text
    2023/04/30 13:49:34 [error] 19381#19381: *1082680 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 429, body: Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
    ```

  - The logs usually associated with high QPS look like the above. The error is: `Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased`.
  - Refer to [Loki documentation](https://grafana.com/docs/loki/latest/configuration/#limits_config) to add limits on the amount of default and burst logs, such as `ingestion_rate_mb` and `ingestion_burst_size_mb`.

    As the test during development, setting the `ingestion_burst_size_mb` to 100 allows APISIX to push the logs correctly at least at 10000 RPS.
