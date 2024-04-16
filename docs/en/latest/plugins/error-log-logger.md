---
title: error-log-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Error log logger
description: This document contains information about the Apache APISIX error-log-logger Plugin.
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

## Description

The `error-log-logger` Plugin is used to push APISIX's error logs (`error.log`) to TCP, [Apache SkyWalking](https://skywalking.apache.org/), Apache Kafka or ClickHouse servers. You can also set the error log level to send the logs to server.

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                             | Type    | Required | Default                        | Valid values                                                                            | Description                                                                                                  |
|----------------------------------|---------|----------|--------------------------------|-----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| tcp.host                         | string  | True     |                                |                                                                                         | IP address or the hostname of the TCP server.                                                                |
| tcp.port                         | integer | True     |                                | [0,...]                                                                                 | Target upstream port.                                                                                        |
| tcp.tls                          | boolean | False    | false                          |                                                                                         | When set to `true` performs SSL verification.                                                                |
| tcp.tls_server_name              | string  | False    |                                |                                                                                         | Server name for the new TLS extension SNI.                                                                   |
| skywalking.endpoint_addr         | string  | False    | http://127.0.0.1:12900/v3/logs |                                                                                         | Apache SkyWalking HTTP endpoint.                                                                             |
| skywalking.service_name          | string  | False    | APISIX                         |                                                                                         | Service name for the SkyWalking reporter.                                                                    |
| skywalking.service_instance_name | String  | False    | APISIX Instance Name           |                                                                                         | Service instance name for the SkyWalking reporter. Set it to `$hostname` to directly get the local hostname. |
| clickhouse.endpoint_addr         | String  | False    | http://127.0.0.1:8213          |                                                                                         | ClickHouse endpoint.                                                                                         |
| clickhouse.user                  | String  | False    | default                        |                                                                                         | ClickHouse username.                                                                                         |
| clickhouse.password              | String  | False    |                                |                                                                                         | ClickHouse password.                                                                                         |
| clickhouse.database              | String  | False    |                                |                                                                                         | Name of the database to store the logs.                                                                      |
| clickhouse.logtable              | String  | False    |                                |                                                                                         | Table name to store the logs.                                                                                |
| kafka.brokers                    | array   | True     |                |                       | List of Kafka brokers (nodes).                                                                                                                                                                                                                                                                                                                   |
| kafka.brokers.host                     | string  | True     |                |                       | The host of Kafka broker, e.g, `192.168.1.1`.                                                                                                                                                                                                                                                                                                                   |
| kafka.brokers.port                     | integer | True     |                |   [0, 65535]                  |  The port of Kafka broker                                                                                                                                                                                                                                                                                                                  |
| kafka.brokers.sasl_config              | object  | False    |                |                               |  The sasl config of Kafka broker                                                                                                                                                                                                                                                                                                                 |
| kafka.brokers.sasl_config.mechanism    | string  | False    | "PLAIN"          | ["PLAIN"]           |     The mechaism of sasl config                                                                                                                                                                                                                                                                                                             |
| kafka.brokers.sasl_config.user         | string  | True     |                  |                     |  The user of sasl_config. If sasl_config exists, it's required.                                                                                                                                                                                                                                                                                             |
| kafka.brokers.sasl_config.password     | string  | True     |                  |                     | The password of sasl_config. If sasl_config exists, it's required.                                                                                                                                                                                                                                                                                                 |
| kafka.kafka_topic                      | string  | True     |                |                       | Target topic to push the logs for organisation.                                                                                                                                                                                                                                                                                                  |
| kafka.producer_type                    | string  | False    | async          | ["async", "sync"]     | Message sending mode of the producer.                                                                                                                                                                                                                                                                                                            |
| kafka.required_acks                    | integer | False    | 1              | [0, 1, -1]            | Number of acknowledgements the leader needs to receive for the producer to consider the request complete. This controls the durability of the sent records. The attribute follows the same configuration as the Kafka `acks` attribute. See [Apache Kafka documentation](https://kafka.apache.org/documentation/#producerconfigs_acks) for more. |
| kafka.key                              | string  | False    |                |                       | Key used for allocating partitions for messages.                                                                                                                                                                                                                                                                                                 |
| kafka.cluster_name           | integer | False    | 1              | [0,...]               | Name of the cluster. Used when there are two or more Kafka clusters. Only works if the `producer_type` attribute is set to `async`.                                                                                                                                                                                                              |
| kafka.meta_refresh_interval | integer | False    | 30              | [1,...]               | `refresh_interval` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) specifies the time to auto refresh the metadata, in seconds.|
| timeout                          | integer | False    | 3                              | [1,...]                                                                                 | Timeout (in seconds) for the upstream to connect and send data.                                              |
| keepalive                        | integer | False    | 30                             | [1,...]                                                                                 | Time in seconds to keep the connection alive after sending data.                                             |
| level                            | string  | False    | WARN                           | ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"] | Log level to filter the error logs. `ERR` is same as `ERROR`.                                                |

NOTE: `encrypt_fields = {"clickhouse.password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```text
["2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:205: load(): new plugins: {"error-log-logger":true}, context: init_worker_by_lua*","\n","2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:255: load_stream(): new plugins: {"limit-conn":true,"ip-restriction":true,"syslog":true,"mqtt-proxy":true}, context: init_worker_by_lua*","\n"]
```

## Enable Plugin

To enable the Plugin, you can add it in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - request-id
  - hmac-auth
  - api-breaker
  - error-log-logger
```

Once you have enabled the Plugin, you can configure it through the Plugin metadata.

### Configuring TCP server address

You can set the TCP server address by configuring the Plugin metadata as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "tcp": {
    "host": "127.0.0.1",
    "port": 1999
  },
  "inactive_timeout": 1
}'
```

### Configuring SkyWalking OAP server address

You can configure the SkyWalking OAP server address as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "skywalking": {
    "endpoint_addr":"http://127.0.0.1:12800/v3/logs"
  },
  "inactive_timeout": 1
}'
```

### Configuring ClickHouse server details

The Plugin sends the error log as a string to the `data` field of a table in your ClickHouse server.

You can configure it as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "clickhouse": {
      "user": "default",
      "password": "a",
      "database": "error_log",
      "logtable": "t",
      "endpoint_addr": "http://127.0.0.1:8123"
  }
}'
```

### Configuring Kafka server

The Plugin sends the error log to Kafka, you can configure it as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
   "kafka":{
      "brokers":[
         {
            "host":"127.0.0.1",
            "port":9092
         }
      ],
      "kafka_topic":"test2"
   },
   "level":"ERROR",
   "inactive_timeout":1
}'
```

## Delete Plugin

To remove the Plugin, you can remove it from your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - request-id
  - hmac-auth
  - api-breaker
  # - error-log-logger
```
