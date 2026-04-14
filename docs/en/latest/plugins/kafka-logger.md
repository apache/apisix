---
title: kafka-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Kafka Logger
description: This document contains information about the Apache APISIX kafka-logger Plugin.
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

The `kafka-logger` Plugin is used to push logs as JSON objects to Apache Kafka clusters. It works as a Kafka client driver for the ngx_lua Nginx module.

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                   | Type    | Required | Default        | Valid values          | Description                                                                                                                                                                                                                                                                                                                                      |
| ---------------------- | ------- | -------- | -------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| broker_list            | object  | True     |                |                       | Deprecated, use `brokers` instead. List of Kafka brokers.  (nodes).                                                                                                                                                                                                                                                                                                                   |
| brokers                | array   | True     |                |                       | List of Kafka brokers (nodes).                                                                                                                                                                                                                                                                                                                   |
| brokers.host           | string  | True     |                |                       | The host of Kafka broker, e.g, `192.168.1.1`.                                                                                                                                                                                                                                                                                                                   |
| brokers.port           | integer | True     |                |   [0, 65535]                  |  The port of Kafka broker                                                                                                                                                                                                                                                                                                                  |
| brokers.sasl_config    | object  | False    |                |                               |  The sasl config of Kafka broker                                                                                                                                                                                                                                                                                                                 |
| brokers.sasl_config.mechanism  | string  | False    | "PLAIN"          | ["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"]           |     The mechaism of sasl config                                                                                                                                                                                                                                                                                                             |
| brokers.sasl_config.user       | string  | True     |                  |                     |  The user of sasl_config. If sasl_config exists, it's required.                                                                                                                                                                                                                                                                                             |
| brokers.sasl_config.password   | string  | True     |                  |                     | The password of sasl_config. If sasl_config exists, it's required.                                                                                                                                                                                                                                                                                                 |
| kafka_topic            | string  | True     |                |                       | Target topic to push the logs for organisation.                                                                                                                                                                                                                                                                                                  |
| producer_type          | string  | False    | async          | ["async", "sync"]     | Message sending mode of the producer.                                                                                                                                                                                                                                                                                                            |
| required_acks          | integer | False    | 1              | [1, -1]            | Number of acknowledgements the leader needs to receive for the producer to consider the request complete. This controls the durability of the sent records. The attribute follows the same configuration as the Kafka `acks` attribute. `required_acks` cannot be 0. See [Apache Kafka documentation](https://kafka.apache.org/documentation/#producerconfigs_acks) for more. |
| key                    | string  | False    |                |                       | Key used for allocating partitions for messages.                                                                                                                                                                                                                                                                                                 |
| timeout                | integer | False    | 3              | [1,...]               | Timeout for the upstream to send data.                                                                                                                                                                                                                                                                                                           |
| name                   | string  | False    | "kafka logger" |                       | Unique identifier for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                                                                                                                                                                                                  |
| meta_format            | enum    | False    | "default"      | ["default"，"origin"] | Format to collect the request information. Setting to `default` collects the information in JSON format and `origin` collects the information with the original HTTP request. See [examples](#meta_format-example) below.                                                                                                                        |
| log_format | object | False    |   |               | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| include_req_body       | boolean | False    | false          | [false, true]         | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                                                                                                                                                 |
| include_req_body_expr  | array   | False    |                |                       | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| max_req_body_bytes     | integer | False    | 524288         | >=1                   | Maximum request body allowed in bytes. Request bodies falling within this limit will be pushed to Kafka. If the size exceeds the configured value, the body will be truncated before being pushed to Kafka.                                                                                                                                                                                                  |
| include_resp_body      | boolean | False    | false          | [false, true]         | When set to `true` includes the response body in the log.                                                                                                                                                                                                                                                                                        |
| include_resp_body_expr | array   | False    |                |                       | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |
| max_resp_body_bytes    | integer | False    | 524288         | >=1                   | Maximum response body allowed in bytes. Response bodies falling within this limit will be pushed to Kafka. If the size exceeds the configured value, the body will be truncated before being pushed to Kafka.                                                                                                                                                                                                  |
| cluster_name           | integer | False    | 1              | [0,...]               | Name of the cluster. Used when there are two or more Kafka clusters. Only works if the `producer_type` attribute is set to `async`.                                                                                                                                                                                                              |
| producer_batch_num     | integer | optional    | 200            | [1,...]               | `batch_num` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka). The merge message and batch is send to the server. Unit is message count.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| producer_batch_size    | integer | optional    | 1048576        | [0,...]               | `batch_size` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) in bytes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| producer_max_buffering | integer | optional    | 50000          | [1,...]               | `max_buffering` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) representing maximum buffer size. Unit is message count.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| producer_time_linger   | integer | optional    | 1              | [1,...]               | `flush_time` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) in seconds.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| meta_refresh_interval | integer | optional    | 30              | [1,...]               | `refresh_interval` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) specifies the time to auto refresh the metadata, in seconds.                                                                                                                                                                                                                                                                                                           |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

:::info IMPORTANT

The data is first written to a buffer. When the buffer exceeds the `batch_max_size` or `buffer_duration` attribute, the data is sent to the Kafka server and the buffer is flushed.

If the process is successful, it will return `true` and if it fails, returns `nil` with a string with the "buffer overflow" error.

:::

### meta_format example

- `default`:

  ```json
  {
    "upstream": "127.0.0.1:1980",
    "start_time": 1619414294760,
    "client_ip": "127.0.0.1",
    "service_id": "",
    "route_id": "1",
    "request": {
      "querystring": {
        "ab": "cd"
      },
      "size": 90,
      "uri": "/hello?ab=cd",
      "url": "http://localhost:1984/hello?ab=cd",
      "headers": {
        "host": "localhost",
        "content-length": "6",
        "connection": "close"
      },
      "body": "abcdef",
      "method": "GET"
    },
    "response": {
      "headers": {
        "connection": "close",
        "content-type": "text/plain; charset=utf-8",
        "date": "Mon, 26 Apr 2021 05:18:14 GMT",
        "server": "APISIX/2.5",
        "transfer-encoding": "chunked"
      },
      "size": 190,
      "status": 200
    },
    "server": {
      "hostname": "localhost",
      "version": "2.5"
    },
    "latency": 0
  }
  ```

- `origin`:

  ```http
  GET /hello?ab=cd HTTP/1.1
  host: localhost
  content-length: 6
  connection: close

  abcdef
  ```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `kafka-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/kafka-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## Enable Plugin

The example below shows how you can enable the `kafka-logger` Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "kafka-logger": {
           "brokers" : [
             {
               "host" :"127.0.0.1",
               "port" : 9092
             }
            ],
           "kafka_topic" : "test2",
           "key" : "key1",
           "batch_max_size": 1,
           "name": "kafka logger"
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

This Plugin also supports pushing to more than one broker at a time. You can specify multiple brokers in the Plugin configuration as shown below:

```json
 "brokers" : [
    {
      "host" :"127.0.0.1",
      "port" : 9092
    },
    {
      "host" :"127.0.0.1",
      "port" : 9093
    }
],
```

## Example usage

Now, if you make a request to APISIX, it will be logged in your Kafka server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `kafka-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
