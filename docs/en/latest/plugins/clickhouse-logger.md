---
title: clickhouse-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ClickHouse Logger
description: The clickhouse-logger Plugin pushes request and response logs to ClickHouse databases in batches and supports the customization of log formats to enhance data management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/clickhouse-logger" />
</head>

## Description

The `clickhouse-logger` Plugin pushes request and response logs to [ClickHouse](https://clickhouse.com/) database in batches and supports the customization of log formats.

## Attributes

| Name                   | Type        | Required | Default             | Valid values      | Description                                                                                                                                                                                                                                                                                                    |
|------------------------|-------------|----------|---------------------|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint_addrs         | array       | True     |                     |                   | ClickHouse endpoints.                                                                                                                                                                                                                                                                                          |
| database               | string      | True     |                     |                   | Name of the database to store the logs.                                                                                                                                                                                                                                                                        |
| logtable               | string      | True     |                     |                   | Name of the table that stores the logs.                                                                                                                                                                                                                                                                        |
| user                   | string      | True     |                     |                   | ClickHouse username. From APISIX 3.16.0, supports referencing values from environment variables using the `$ENV://` prefix or from a secret manager using the `$secret://` prefix. For more information, see [secrets](../terminology/secret.md).                                                               |
| password               | string      | True     |                     |                   | ClickHouse password. From APISIX 3.16.0, supports referencing values from environment variables using the `$ENV://` prefix or from a secret manager using the `$secret://` prefix. For more information, see [secrets](../terminology/secret.md).                                                               |
| timeout                | integer     | False    | 3                   | greater than 0    | Time in seconds to keep the connection alive after sending a request.                                                                                                                                                                                                                                          |
| ssl_verify             | boolean     | False    | true                |                   | If `true`, verify SSL.                                                                                                                                                                                                                                                                                         |
| log_format             | object      | False    |                     |                   | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. You can also configure log format on a global scale using [Plugin Metadata](#plugin-metadata). |
| include_req_body       | boolean     | False    | false               |                   | If `true`, include the request body in the log. Note that if the request body is too big to be kept in the memory, it cannot be logged due to NGINX's limitations.                                                                                                                                             |
| include_req_body_expr  | array       | False    |                     |                   | An array of one or more conditions in the form of [APISIX expressions](https://github.com/api7/lua-resty-expr). Used when `include_req_body` is `true`. Request body is only logged when the expressions evaluate to `true`.                                                                                   |
| include_resp_body      | boolean     | False    | false               |                   | If `true`, include the response body in the log.                                                                                                                                                                                                                                                               |
| include_resp_body_expr | array       | False    |                     |                   | An array of one or more conditions in the form of [APISIX expressions](https://github.com/api7/lua-resty-expr). Used when `include_resp_body` is `true`. Response body is only logged when the expressions evaluate to `true`.                                                                                 |
| max_req_body_bytes     | integer     | False    | 524288              | >= 1              | Maximum request body size in bytes to include in the log. If the request body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                                                                                                                       |
| max_resp_body_bytes    | integer     | False    | 524288              | >= 1              | Maximum response body size in bytes to include in the log. If the response body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                                                                                                                     |
| name                   | string      | False    | "clickhouse logger" |                   | Unique identifier of the Plugin for the batch processor. If you use [Prometheus](./prometheus.md) to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                           |
| batch_max_size         | integer     | False    | 1000                | greater than 0    | The number of log entries allowed in one batch. Once reached, the batch will be sent to ClickHouse. Setting this parameter to `1` means immediate processing.                                                                                                                                                  |
| inactive_timeout       | integer     | False    | 5                   | greater than 0    | The maximum time in seconds to wait for new logs before sending the batch to the logging service. The value should be smaller than `buffer_duration`.                                                                                                                                                          |
| buffer_duration        | integer     | False    | 60                  | greater than 0    | The maximum time in seconds from the earliest entry allowed before sending the batch to the logging service.                                                                                                                                                                                                   |
| retry_delay            | integer     | False    | 1                   | >= 0              | The time interval in seconds to retry sending the batch to the logging service if the batch was not successfully sent.                                                                                                                                                                                         |
| max_retry_count        | integer     | False    | 60                  | >= 0              | The maximum number of unsuccessful retries allowed before dropping the log entries.                                                                                                                                                                                                                            |

NOTE: `encrypt_fields = {"password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

NOTE: In addition, you can use Environment Variables or APISIX Secret to store and reference Plugin attributes. APISIX currently supports storing secrets in two ways: [Environment Variables and HashiCorp Vault](../terminology/secret.md).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Plugin Metadata

| Name               | Type    | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                     |
|--------------------|---------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False    |         |              | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. This configuration is global and applies to all Routes and Services that use the `clickhouse-logger` Plugin. |
| max_pending_entries | integer | False   |         | >= 1         | Maximum number of unprocessed entries allowed in the batch processor. When this limit is reached, new entries will be dropped until the backlog is reduced.                                                                                                                      |

## Examples

The examples below demonstrate how you can configure the `clickhouse-logger` Plugin for different use cases.

To follow along with the examples, start a sample ClickHouse server with user `default` and empty password:

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name clickhouse-server clickhouse/clickhouse-server
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log in the Default Log Format

The following example demonstrates how to log requests in the default log format.

Create a table named `default_logs` in your ClickHouse database with columns corresponding to the default log format:

```shell
curl "http://127.0.0.1:8123" -X POST -d '
  CREATE TABLE default.default_logs (
    host String, 
    client_ip String, 
    route_id String, 
    service_id String, 
    start_time String, 
    latency String,
    upstream_latency String, 
    apisix_latency String, 
    consumer String, 
    request String, 
    response String, 
    server String
  )
  ENGINE = MergeTree()
  ORDER BY (`start_time`)
  PRIMARY KEY(`start_time`)
' --user default:
```

Create a Route with the `clickhouse-logger` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "clickhouse-logger-route",
    "uri": "/get",
    "plugins": {
      "clickhouse-logger": {
        "user": "default",
        "password": "",
        "database": "default",
        "logtable": "default_logs",
        "endpoint_addrs": ["http://127.0.0.1:8123"]
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

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

Send a request to ClickHouse to see the log entries:

```shell
echo 'SELECT * FROM default.default_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

You should see a log entry similar to the following:

```text

┏━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━┓
┃ host ┃ client_ip  ┃ route_id                ┃ service_id ┃ start_time    ┃ latency         ┃ upstream_latency ┃ apisix_latency  ┃ consumer ┃ request ┃ response ┃ server  ┃
┡━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━┩
│      │ 172.19.0.1 │ clickhouse-logger-route │            │ 1703026935235 │ 481.00018501282 │ 473              │ 8.0001850128174 │          │ {...}   │ {...}    │ {...}   │
└──────┴────────────┴─────────────────────────┴────────────┴───────────────┴─────────────────┴──────────────────┴─────────────────┴──────────┴─────────┴──────────┴─────────┘
```

### Customize Log Format With Plugin Metadata

The following example demonstrates how to customize the log format using Plugin Metadata and [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html).

Plugin Metadata is global in scope and applies to all instances of `clickhouse-logger`. If the log format configured on an individual Plugin instance differs from the log format configured in Plugin Metadata, the instance-level configuration takes precedence.

Create a table named `custom_logs` in your ClickHouse database with columns corresponding to your customized log format:

```shell
curl "http://127.0.0.1:8123" -X POST -d '
  CREATE TABLE default.custom_logs (
    host String,
    client_ip String,
    route_id String,
    service_id String,
    `@timestamp` String,
    PRIMARY KEY(`@timestamp`)
  )
  ENGINE = MergeTree()
  ORDER BY (`@timestamp`)
' --user default:
```

Create a Route with the `clickhouse-logger` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "clickhouse-logger-route",
    "uri": "/get",
    "plugins": {
      "clickhouse-logger": {
        "user": "default",
        "password": "",
        "database": "default",
        "logtable": "custom_logs",
        "endpoint_addrs": ["http://127.0.0.1:8123"]
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

Configure Plugin Metadata for `clickhouse-logger`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/clickhouse-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "client_ip": "$remote_addr",
      "route_id": "$route_id",
      "service_id": "$service_id",
      "@timestamp": "$time_iso8601"
    }
  }'
```

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

Send a request to ClickHouse to see the log entries:

```shell
echo 'SELECT * FROM default.custom_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

You should see a log entry similar to the following:

```text
┏━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ host      ┃ client_ip  ┃ route_id                ┃ service_id ┃ @timestamp                ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ 127.0.0.1 │ 172.19.0.1 │ clickhouse-logger-route │            │ 2023-12-19T23:25:43+00:00 │
└───────────┴────────────┴─────────────────────────┴────────────┴───────────────────────────┘
```
