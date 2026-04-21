---
title: error-log-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Error log logger
description: The error-log-logger Plugin pushes APISIX's error logs to TCP, Apache SkyWalking, Apache Kafka, or ClickHouse servers, in batches. You can specify the severity level of which the Plugin should send the corresponding logs.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/error-log-logger" />
</head>

## Description

The `error-log-logger` Plugin pushes APISIX's error logs (`error.log`) to TCP, [Apache SkyWalking](https://skywalking.apache.org/), Apache Kafka, or ClickHouse servers, in batches. You can specify the severity level of which the Plugin should send the corresponding logs.

The Plugin is disabled by default. Once enabled, it will automatically start pushing error logs to remote servers. You should configure remote server details in Plugin metadata only, instead of on other resources, such as Routes.

## Plugin Metadata

There are no attributes to configure this Plugin on Routes or Services. All configuration is done through Plugin metadata.

| Name                                    | Type    | Required | Default                        | Valid values                                                                            | Description                                                                                                                                         |
| --------------------------------------- | ------- | -------- | ------------------------------ | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| tcp                                     | object  | False    |                                |                                                                                         | TCP server configurations.                                                                                                                          |
| tcp.host                                | string  | True     |                                |                                                                                         | IP address or the hostname of the TCP server.                                                                                                       |
| tcp.port                                | integer | True     |                                | [0,...]                                                                                 | Target upstream port.                                                                                                                               |
| tcp.tls                                 | boolean | False    | false                          |                                                                                         | When set to `true`, performs SSL verification.                                                                                                      |
| tcp.tls_server_name                     | string  | False    |                                |                                                                                         | Server name for the new TLS extension SNI.                                                                                                          |
| skywalking                              | object  | False    |                                |                                                                                         | SkyWalking server configurations.                                                                                                                   |
| skywalking.endpoint_addr                | string  | False    | http://127.0.0.1:12900/v3/logs |                                                                                         | Address of the SkyWalking server.                                                                                                                   |
| skywalking.service_name                 | string  | False    | APISIX                         |                                                                                         | Service name for the SkyWalking reporter.                                                                                                           |
| skywalking.service_instance_name        | string  | False    | APISIX Instance Name           |                                                                                         | Service instance name for the SkyWalking reporter. Set it to `$hostname` to directly get the local hostname.                                        |
| clickhouse                              | object  | False    |                                |                                                                                         | ClickHouse server configurations.                                                                                                                   |
| clickhouse.endpoint_addr                | string  | False    | http://127.0.0.1:8123          |                                                                                         | ClickHouse endpoint.                                                                                                                                |
| clickhouse.user                         | string  | False    | default                        |                                                                                         | ClickHouse username.                                                                                                                                |
| clickhouse.password                     | string  | False    |                                |                                                                                         | ClickHouse password. The password is encrypted with AES before being stored in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields). |
| clickhouse.database                     | string  | False    |                                |                                                                                         | Name of the database to store the logs.                                                                                                             |
| clickhouse.logtable                     | string  | False    |                                |                                                                                         | Table name to store the logs. The table should have a `data` column where the Plugin will push logs to.                                             |
| kafka                                   | object  | False    |                                |                                                                                         | Kafka server configurations.                                                                                                                        |
| kafka.brokers                           | array   | True     |                                |                                                                                         | List of Kafka broker nodes.                                                                                                                         |
| kafka.brokers[].host                    | string  | True     |                                |                                                                                         | The host of the Kafka broker.                                                                                                                       |
| kafka.brokers[].port                    | integer | True     |                                | [0, 65535]                                                                              | The port of the Kafka broker.                                                                                                                       |
| kafka.brokers[].sasl_config             | object  | False    |                                |                                                                                         | The SASL configuration of the Kafka broker.                                                                                                         |
| kafka.brokers[].sasl_config.mechanism   | string  | False    | PLAIN                          | ["PLAIN"]                                                                               | The mechanism of SASL configuration.                                                                                                               |
| kafka.brokers[].sasl_config.user        | string  | True     |                                |                                                                                         | The user of SASL configuration. Required if `sasl_config` is present.                                                                              |
| kafka.brokers[].sasl_config.password    | string  | True     |                                |                                                                                         | The password of SASL configuration. Required if `sasl_config` is present.                                                                          |
| kafka.kafka_topic                       | string  | True     |                                |                                                                                         | Target topic to push the logs for organization.                                                                                                     |
| kafka.producer_type                     | string  | False    | async                          | ["async", "sync"]                                                                       | Message sending mode of the producer.                                                                                                               |
| kafka.required_acks                     | integer | False    | 1                              | [-1, 1]                                                                                 | Number of acknowledgements the leader needs to receive for the producer to consider the request complete. See [Apache Kafka documentation](https://kafka.apache.org/documentation/#producerconfigs_acks) for more. `acks=0` is not yet supported. |
| kafka.key                               | string  | False    |                                |                                                                                         | Key used for allocating partitions for messages.                                                                                                    |
| kafka.cluster_name                      | integer | False    | 1                              | [0,...]                                                                                 | Name of the cluster. Used when there are two or more Kafka clusters. Only works if `producer_type` is set to `async`.                               |
| kafka.meta_refresh_interval             | integer | False    | 30                             | [1,...]                                                                                 | Time interval in seconds to auto-refresh the metadata. Same as the `refresh_interval` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka). |
| timeout                                 | integer | False    | 3                              | [1,...]                                                                                 | Time in seconds to keep the connection alive after sending a request.                                                                               |
| keepalive                               | integer | False    | 30                             | [1,...]                                                                                 | Time in seconds to keep the connection alive after sending data.                                                                                    |
| level                                   | string  | False    | WARN                           | ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"] | Severity level to filter the error logs. Note that `ERR` is the same as `ERROR`.                                                                   |
| name                                    | string  | False    | error-log-logger               |                                                                                         | Unique identifier of the Plugin for the batch processor.                                                                                            |
| batch_max_size                          | integer | False    | 1000                           | [1,...]                                                                                 | Maximum number of log entries per batch. Once reached, the batch is sent to the configured logging service. Set to `1` for immediate processing.   |
| inactive_timeout                        | integer | False    | 5                              | [1,...]                                                                                 | Maximum time in seconds to wait for new logs before sending the batch. The value should be smaller than `buffer_duration`.                          |
| buffer_duration                         | integer | False    | 60                             | [1,...]                                                                                 | Maximum time in seconds from the earliest entry allowed before sending the batch.                                                                   |
| retry_delay                             | integer | False    | 1                              | [0,...]                                                                                 | Time interval in seconds to retry sending the batch if the previous attempt failed.                                                                 |
| max_retry_count                         | integer | False    | 60                             | [0,...]                                                                                 | Maximum number of unsuccessful retries before dropping the log entries.                                                                             |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```text
["2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:205: load(): new plugins: {"error-log-logger":true}, context: init_worker_by_lua*","\n","2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:255: load_stream(): new plugins: {"limit-conn":true,"ip-restriction":true,"syslog":true,"mqtt-proxy":true}, context: init_worker_by_lua*","\n"]
```

## Enable Plugin

The `error-log-logger` Plugin is disabled by default. To enable the Plugin, add it to your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - error-log-logger
```

Reload APISIX for the change to take effect.

Once the Plugin is enabled, configure it through Plugin metadata as shown in the examples below.

## Examples

The following examples demonstrate how you can configure the `error-log-logger` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Send Logs to TCP Server

The following example demonstrates how to configure the `error-log-logger` Plugin to send error logs to a TCP server.

Start a TCP server listening on port `19000`:

```shell
nc -l 19000
```

Configure the Plugin metadata, setting the TCP server host and port, and the severity level to `INFO` so most logs will be sent for easier verification:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "tcp": {
      "host": "192.168.2.103",
      "port": 19000
    },
    "level": "INFO"
  }'
```

To verify, you can manually generate a log at `warn` level by reloading APISIX. In the terminal session where netcat is listening, you should see a log entry similar to the following:

```text
2025/01/26 20:15:29 [warn] 211#211: *35552 [lua] plugin.lua:205: load(): new plugins: {...}, context: init_worker_by_lua*
```

### Send Logs to SkyWalking

The following example demonstrates how to configure the `error-log-logger` Plugin to send error logs to SkyWalking.

Start a SkyWalking storage, OAP, and Booster UI with Docker Compose, following [SkyWalking's documentation](https://skywalking.apache.org/docs/main/next/en/setup/backend/backend-docker/). Once set up, the OAP server should be listening on `12800` and you should be able to access the UI at [http://localhost:8080](http://localhost:8080).

Configure the Plugin metadata, setting the SkyWalking endpoint address and the severity level to `INFO` so most logs will be sent for easier verification:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "skywalking": {
      "endpoint_addr": "http://192.168.2.103:12800/v3/logs"
    },
    "level": "INFO"
  }'
```

To verify, you can manually generate a log at `warn` level by reloading APISIX. In the SkyWalking UI, navigate to **General Service** > **Services**. You should see a service called `APISIX` with log entries.

### Send Logs to ClickHouse

The following example demonstrates how to configure the `error-log-logger` Plugin to send error logs to ClickHouse.

Start a sample ClickHouse server with user `default` and empty password:

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name clickhouse-server clickhouse/clickhouse-server
```

In ClickHouse database `default`, create a table named `default_logs` with a `data` column. Note that the `data` column is expected by the Plugin to push logs to:

```shell
curl "http://127.0.0.1:8123" -X POST -d '
  CREATE TABLE default.default_logs (
    data String,
    PRIMARY KEY(`data`)
  )
  ENGINE = MergeTree()
' --user default:
```

Configure the Plugin metadata with the ClickHouse server details. Set the severity level to `INFO` so most logs will be sent for easier verification:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "clickhouse": {
      "endpoint_addr": "http://192.168.2.103:8123",
      "user": "default",
      "password": "",
      "database": "default",
      "logtable": "default_logs"
    },
    "level": "INFO"
  }'
```

To verify, you can manually generate a log at `warn` level by reloading APISIX. Then send a request to ClickHouse to see the log entries:

```shell
echo 'SELECT * FROM default.default_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

### Send Logs to Kafka

The following example demonstrates how to configure the `error-log-logger` Plugin to send error logs to a Kafka server.

Configure the Plugin metadata with the Kafka broker details:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "kafka": {
      "brokers": [
        {
          "host": "127.0.0.1",
          "port": 9092
        }
      ],
      "kafka_topic": "apisix-error-logs"
    },
    "level": "ERROR",
    "inactive_timeout": 1
  }'
```
