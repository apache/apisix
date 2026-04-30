---
title: kafka-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Kafka Logger
description: The kafka-logger Plugin pushes request and response logs as JSON objects to Apache Kafka clusters in batches, allowing for customizable log formats to enhance data management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/kafka-logger" />
</head>

## Description

The `kafka-logger` Plugin pushes request and response logs as JSON objects to Apache Kafka clusters in batches and supports the customization of log formats.

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                             | Type    | Required | Default        | Valid values                                      | Description                                                                                                                                                                                                                                                                                                                                      |
| -------------------------------- | ------- | -------- | -------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| broker_list                      | object  | False    |                |                                                   | Deprecated, use `brokers` instead. List of Kafka brokers (nodes).                                                                                                                                                                                                                                                                                |
| brokers                          | array   | True     |                |                                                   | List of Kafka brokers (nodes).                                                                                                                                                                                                                                                                                                                   |
| brokers.host                     | string  | True     |                |                                                   | The host of Kafka broker, e.g. `192.168.1.1`.                                                                                                                                                                                                                                                                                                    |
| brokers.port                     | integer | True     |                | [1, 65535]                                        | The port of Kafka broker.                                                                                                                                                                                                                                                                                                                        |
| brokers.sasl_config              | object  | False    |                |                                                   | The SASL config of Kafka broker.                                                                                                                                                                                                                                                                                                                 |
| brokers.sasl_config.mechanism    | string  | False    | "PLAIN"        | ["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"]       | The mechanism of SASL config.                                                                                                                                                                                                                                                                                                                    |
| brokers.sasl_config.user         | string  | True     |                |                                                   | The user of `sasl_config`. Required if `sasl_config` is configured.                                                                                                                                                                                                                                                                              |
| brokers.sasl_config.password     | string  | True     |                |                                                   | The password of `sasl_config`. Required if `sasl_config` is configured.                                                                                                                                                                                                                                                                          |
| kafka_topic                      | string  | True     |                |                                                   | Target topic to push the logs.                                                                                                                                                                                                                                                                                                                   |
| producer_type                    | string  | False    | async          | ["async", "sync"]                                 | Message sending mode of the producer.                                                                                                                                                                                                                                                                                                            |
| required_acks                    | integer | False    | 1              | [1, -1]                                           | Number of acknowledgements the leader needs to receive for the producer to consider the request complete. This controls the durability of the sent records. The attribute follows the same configuration as the Kafka `acks` attribute. `required_acks` cannot be 0. See [Apache Kafka documentation](https://kafka.apache.org/documentation/#producerconfigs_acks) for more. |
| key                              | string  | False    |                |                                                   | Key used for allocating partitions for messages.                                                                                                                                                                                                                                                                                                 |
| timeout                          | integer | False    | 3              | [1,...]                                           | Timeout in seconds for the upstream to send data.                                                                                                                                                                                                                                                                                                |
| name                             | string  | False    | "kafka logger" |                                                   | Unique identifier for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                                                                                              |
| meta_format                      | enum    | False    | "default"      | ["default","origin"]                              | Format to collect the request information. Setting to `default` collects the information in JSON format and `origin` collects the information with the original HTTP request. See [examples](#meta_format-example) below.                                                                                                                         |
| log_format                       | object  | False    |                |                                                   | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`.                                           |
| include_req_body                 | boolean | False    | false          | [false, true]                                     | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to NGINX's limitations.                                                                                                                                                                                 |
| include_req_body_expr            | array   | False    |                |                                                   | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| max_req_body_bytes               | integer | False    | 524288         | >=1                                               | Maximum request body size in bytes to push to Kafka. If the size exceeds the configured value, the body will be truncated before being pushed.                                                                                                                                                                                                   |
| include_resp_body                | boolean | False    | false          | [false, true]                                     | When set to `true` includes the response body in the log.                                                                                                                                                                                                                                                                                        |
| include_resp_body_expr           | array   | False    |                |                                                   | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |
| max_resp_body_bytes              | integer | False    | 524288         | >=1                                               | Maximum response body size in bytes to push to Kafka. If the size exceeds the configured value, the body will be truncated before being pushed.                                                                                                                                                                                                  |
| cluster_name                     | integer | False    | 1              | [1,...]                                           | Name of the cluster. Used when there are two or more Kafka clusters. Only works if the `producer_type` attribute is set to `async`.                                                                                                                                                                                                              |
| producer_batch_num               | integer | False    | 200            | [1,...]                                           | `batch_num` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka). Merges messages and sends them in batches. Unit is message count.                                                                                                                                                                                     |
| producer_batch_size              | integer | False    | 1048576        | [0,...]                                           | `batch_size` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) in bytes.                                                                                                                                                                                                                                            |
| producer_max_buffering           | integer | False    | 50000          | [1,...]                                           | `max_buffering` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) representing maximum buffer size. Unit is message count.                                                                                                                                                                                           |
| producer_time_linger             | integer | False    | 1              | [1,...]                                           | `flush_time` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) in seconds.                                                                                                                                                                                                                                          |
| meta_refresh_interval            | integer | False    | 30             | [1,...]                                           | `refresh_interval` parameter in [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) that specifies the interval to auto-refresh the metadata, in seconds.                                                                                                                                                                          |

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

| Name                | Type    | Required | Default | Description                                                                                                                                                                                                                                             |
| ------------------- | ------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format          | object  | False    |         | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False    |         | Maximum number of pending entries that can be buffered in the batch processor before it starts dropping them.                                                                                                                                           |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `kafka-logger` Plugin.

:::

## Examples

The examples below demonstrate how to configure the `kafka-logger` Plugin for different use cases.

To follow along the examples, start a sample Kafka cluster using Docker Compose:

```yaml title="docker-compose.yml"
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.8.0
    container_name: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  kafka:
    image: confluentinc/cp-kafka:7.8.0
    container_name: kafka
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://127.0.0.1:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
    ports:
      - "9092:9092"
```

Start containers:

```shell
docker compose up -d
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log in Different Meta Log Formats

The following example demonstrates how to enable the `kafka-logger` Plugin on a Route, which logs client requests and pushes logs to Kafka. You will also understand the differences between the `default` and `origin` meta log formats.

In a separate terminal, wait for messages in the configured Kafka topic:

```shell
docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic test2 --from-beginning
```

Open a new terminal session for the following steps.

Create a Route with `kafka-logger`. Set `meta_format` to the `default` log format, and set `batch_max_size` to `1` to send the log entry immediately:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "kafka-logger-route",
    "uri": "/get",
    "plugins": {
      "kafka-logger": {
        "meta_format": "default",
        "brokers": [
          {
            "host": "127.0.0.1",
            "port": 9092
          }
        ],
        "kafka_topic": "test2",
        "key": "key1",
        "batch_max_size": 1
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

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

You should see a log entry in the Kafka topic similar to the following:

```json
{
  "latency": 411.00001335144,
  "request": {
    "querystring": {},
    "headers": {
      "host": "127.0.0.1:9080",
      "user-agent": "curl/8.7.1",
      "accept": "*/*",
      "x-forwarded-proto": "http",
      "x-forwarded-host": "127.0.0.1",
      "x-forwarded-port": "9080"
    },
    "method": "GET",
    "size": 83,
    "uri": "/get",
    "url": "http://127.0.0.1:9080/get"
  },
  "response": {
    "headers": {
      "content-length": "233",
      "access-control-allow-credentials": "true",
      "content-type": "application/json",
      "connection": "close",
      "access-control-allow-origin": "*",
      "date": "Fri, 10 Nov 2023 06:02:44 GMT",
      "server": "APISIX/3.16.0"
    },
    "status": 200,
    "size": 475
  },
  "route_id": "kafka-logger-route",
  "client_ip": "127.0.0.1",
  "server": {
    "hostname": "apisix",
    "version": "3.16.0"
  },
  "apisix_latency": 18.00001335144,
  "service_id": "",
  "upstream_latency": 393,
  "start_time": 1699596164550,
  "upstream": "54.90.18.68:80"
}
```

Update the meta log format to `origin`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/kafka-logger-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "kafka-logger": {
        "meta_format": "origin"
      }
    }
  }'
```

Send a request to the Route again to generate a new log entry:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

You should see a log entry in the Kafka topic similar to the following:

```text
GET /get HTTP/1.1
x-forwarded-proto: http
x-forwarded-host: 127.0.0.1
user-agent: curl/8.7.1
x-forwarded-port: 9080
host: 127.0.0.1:9080
accept: */*
```

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how to customize the log format using [plugin metadata](../terminology/plugin-metadata.md) and [built-in variables](../apisix-variable.md) to log specific headers from request and response.

Plugin metadata is used to configure the common metadata fields of all Plugin instances of the same Plugin. It is useful when a Plugin is enabled across multiple resources and requires a universal update to their metadata fields.

First, create a Route with `kafka-logger`. Set `meta_format` to `default` (required for custom log format via plugin metadata) and `batch_max_size` to `1` to send log entries immediately:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "kafka-logger-route",
    "uri": "/get",
    "plugins": {
      "kafka-logger": {
        "meta_format": "default",
        "brokers": [
          {
            "host": "127.0.0.1",
            "port": 9092
          }
        ],
        "kafka_topic": "test2",
        "key": "key1",
        "batch_max_size": 1
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

:::note

If `meta_format` is set to `origin`, log entries will remain in `origin` format regardless of plugin metadata log format configuration.

:::

Next, configure the Plugin metadata for `kafka-logger` to log the custom request header `env` and the response header `Content-Type`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/kafka-logger" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "@timestamp": "$time_iso8601",
      "client_ip": "$remote_addr",
      "env": "$http_env",
      "resp_content_type": "$sent_http_Content_Type"
    }
  }'
```

Send a request to the Route with the `env` header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "env: dev"
```

You should see a log entry in the Kafka topic similar to the following:

```json
{
  "@timestamp": "2023-11-10T23:09:04+00:00",
  "host": "127.0.0.1",
  "client_ip": "127.0.0.1",
  "route_id": "kafka-logger-route",
  "env": "dev",
  "resp_content_type": "application/json"
}
```

### Log Request Bodies Conditionally

The following example demonstrates how to conditionally log request bodies.

Create a Route with `kafka-logger`. Set `include_req_body` to `true` to include the request body, and set `include_req_body_expr` to only include the body when the URL query string `log_body` equals `yes`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "kafka-logger-route",
    "uri": "/post",
    "plugins": {
      "kafka-logger": {
        "brokers": [
          {
            "host": "127.0.0.1",
            "port": 9092
          }
        ],
        "kafka_topic": "test2",
        "key": "key1",
        "batch_max_size": 1,
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
curl -i "http://127.0.0.1:9080/post?log_body=yes" -X POST -d '{"env": "dev"}'
```

You should see the request body logged:

```json
{
  "...",
  "request": {
    "method": "POST",
    "body": "{\"env\": \"dev\"}",
    "size": 179
  }
}
```

Send another request without the URL query string:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -d '{"env": "dev"}'
```

You should not observe the request body in the log.

:::note

If you have customized the `log_format` in addition to setting `include_req_body` or `include_resp_body` to `true`, the Plugin will not include the bodies in the logs. As a workaround, you can use the NGINX variable `$request_body` in the log format:

```json
{
  "kafka-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
