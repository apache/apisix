---
title: kafka-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Kafka Logger
description: kafka-logger 插件将请求和响应日志作为 JSON 对象批量推送到 Apache Kafka 集群，并支持自定义日志格式以便更好地管理数据。
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

## 描述

`kafka-logger` 插件将请求和响应日志作为 JSON 对象批量推送到 Apache Kafka 集群，并支持自定义日志格式。

接收日志数据可能需要一些时间。数据将在 [批处理器](../batch-processor.md) 中的计时器函数到期后自动发送。

## 属性

| 名称                             | 类型    | 是否必需 | 默认值          | 有效值                                            | 描述                                                                                                                                                                                                                                                                        |
| -------------------------------- | ------- | -------- | --------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| broker_list                      | object  | 否       |                 |                                                   | 已废弃，请改用 `brokers` 属性。原指需要推送的 Kafka 的 broker 列表。                                                                                                                                                                                                          |
| brokers                          | array   | 是       |                 |                                                   | 需要推送的 Kafka 的 broker 列表。                                                                                                                                                                                                                                             |
| brokers.host                     | string  | 是       |                 |                                                   | Kafka broker 的节点地址，例如 `192.168.1.1`。                                                                                                                                                                                                                                |
| brokers.port                     | integer | 是       |                 | [1, 65535]                                        | Kafka broker 的节点端口。                                                                                                                                                                                                                                                     |
| brokers.sasl_config              | object  | 否       |                 |                                                   | Kafka broker 的 SASL 配置。                                                                                                                                                                                                                                                  |
| brokers.sasl_config.mechanism    | string  | 否       | "PLAIN"         | ["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"]       | SASL 认证机制。                                                                                                                                                                                                                                                               |
| brokers.sasl_config.user         | string  | 是       |                 |                                                   | SASL 配置中的用户名。如果配置了 `sasl_config`，则必须填写。                                                                                                                                                                                                                  |
| brokers.sasl_config.password     | string  | 是       |                 |                                                   | SASL 配置中的密码。如果配置了 `sasl_config`，则必须填写。                                                                                                                                                                                                                    |
| kafka_topic                      | string  | 是       |                 |                                                   | 用于推送日志的目标 topic。                                                                                                                                                                                                                                                    |
| producer_type                    | string  | 否       | async           | ["async", "sync"]                                 | 生产者发送消息的模式。                                                                                                                                                                                                                                                        |
| required_acks                    | integer | 否       | 1               | [1, -1]                                           | 生产者在确认一个请求发送完成之前需要收到的确认信息数量，用于保证发送请求的可靠性。该属性与 Kafka 的 `acks` 属性配置相同，`required_acks` 不能为 0。详情请参考 [Apache Kafka 文档](https://kafka.apache.org/documentation/#producerconfigs_acks)。                              |
| key                              | string  | 否       |                 |                                                   | 用于消息分区的键。                                                                                                                                                                                                                                                            |
| timeout                          | integer | 否       | 3               | [1,...]                                           | 发送数据的超时时间（秒）。                                                                                                                                                                                                                                                    |
| name                             | string  | 否       | "kafka logger"  |                                                   | 批处理器的唯一标识符。如果使用 Prometheus 监控 APISIX 指标，该名称将以 `apisix_batch_process_entries` 导出。                                                                                                                                                                  |
| meta_format                      | enum    | 否       | "default"       | ["default","origin"]                              | 收集请求信息的格式。设置为 `default` 时以 JSON 格式收集信息，设置为 `origin` 时以 HTTP 原始请求格式收集信息。详情请参考下方 [示例](#meta_format-示例)。                                                                                                                       |
| log_format                       | object  | 否       |                 |                                                   | 以 JSON 键值对声明的日志格式。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。                                                   |
| include_req_body                 | boolean | 否       | false           | [false, true]                                     | 设置为 `true` 时，在日志中包含请求体。**注意**：如果请求体过大无法完全存放在内存中，由于 NGINX 的限制，将无法记录。                                                                                                                                                           |
| include_req_body_expr            | array   | 否       |                 |                                                   | 当 `include_req_body` 设置为 `true` 时的过滤条件。只有当此处设置的表达式计算结果为 `true` 时，才会记录请求体。详情请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。                                                                                          |
| max_req_body_bytes               | integer | 否       | 524288          | >=1                                               | 允许推送到 Kafka 的最大请求体大小（字节）。如果超过该值，请求体在推送前会被截断。                                                                                                                                                                                             |
| include_resp_body                | boolean | 否       | false           | [false, true]                                     | 设置为 `true` 时，在日志中包含响应体。                                                                                                                                                                                                                                        |
| include_resp_body_expr           | array   | 否       |                 |                                                   | 当 `include_resp_body` 设置为 `true` 时的过滤条件。只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。详情请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。                                                                                         |
| max_resp_body_bytes              | integer | 否       | 524288          | >=1                                               | 允许推送到 Kafka 的最大响应体大小（字节）。如果超过该值，响应体在推送前会被截断。                                                                                                                                                                                             |
| cluster_name                     | integer | 否       | 1               | [1,...]                                           | Kafka 集群的名称，在有两个或多个 Kafka 集群时使用。仅当 `producer_type` 设置为 `async` 时有效。                                                                                                                                                                               |
| producer_batch_num               | integer | 否       | 200             | [1,...]                                           | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `batch_num` 参数，聚合消息批量提交，单位为消息条数。                                                                                                                                               |
| producer_batch_size              | integer | 否       | 1048576         | [0,...]                                           | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `batch_size` 参数，单位为字节。                                                                                                                                                                    |
| producer_max_buffering           | integer | 否       | 50000           | [1,...]                                           | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `max_buffering` 参数，表示最大缓冲区大小，单位为条。                                                                                                                                               |
| producer_time_linger             | integer | 否       | 1               | [1,...]                                           | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `flush_time` 参数，单位为秒。                                                                                                                                                                      |
| meta_refresh_interval            | integer | 否       | 30              | [1,...]                                           | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `refresh_interval` 参数，用于指定自动刷新 metadata 的间隔时长，单位为秒。                                                                                                                          |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据），避免频繁提交数据。默认情况下，批处理器每 `5` 秒或队列中的数据达到 `1000` 条时提交数据。如需了解批处理器相关参数设置，请参考[批处理器](../batch-processor.md#配置)配置部分。

:::info 重要

数据首先写入缓冲区。当缓冲区超过 `batch_max_size` 或 `buffer_duration` 设置的值时，数据将发送到 Kafka 服务器并刷新缓冲区。

如果发送成功，则返回 `true`。如果出现错误，则返回 `nil`，并带有描述错误的字符串 `buffer overflow`。

:::

### meta_format 示例

- `default`：

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

- `origin`：

  ```http
  GET /hello?ab=cd HTTP/1.1
  host: localhost
  content-length: 6
  connection: close

  abcdef
  ```

## 插件元数据

你也可以通过配置插件元数据来设置日志格式。可用配置如下：

| 名称                | 类型    | 是否必需 | 默认值 | 描述                                                                                                                                                                                                                                    |
| ------------------- | ------- | -------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format          | object  | 否       |        | 以 JSON 键值对声明的日志格式。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。               |
| max_pending_entries | integer | 否       |        | 批处理器开始丢弃待处理条目之前可缓冲的最大待处理条目数。                                                                                                                                                                                |

:::info 重要

插件元数据配置为全局生效。这意味着它将对所有使用 `kafka-logger` 插件的路由和服务生效。

:::

## 示例

以下示例展示了 `kafka-logger` 插件在不同使用场景下的配置方式。

按照示例操作前，请先使用 Docker Compose 启动一个 Kafka 集群：

```yaml title="docker-compose.yml"
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.8.0
    container_name: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    networks:
      - kafka_net

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
    networks:
      - kafka_net

networks:
  kafka_net:
    driver: bridge
```

启动容器：

```shell
docker compose up -d
```

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用不同的元日志格式记录日志

以下示例演示了如何在路由上启用 `kafka-logger` 插件记录客户端请求并将日志推送到 Kafka，同时介绍 `default` 和 `origin` 元日志格式的区别。

在另一个终端中，等待配置的 Kafka topic 中的消息：

```shell
docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic test2 --from-beginning
```

打开一个新终端，执行以下操作。

创建一条启用 `kafka-logger` 插件的路由。将 `meta_format` 设置为 `default` 日志格式，并将 `batch_max_size` 设置为 `1` 以立即发送日志条目：

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
            "host": "kafka",
            "port": 29092
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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该收到一个 `HTTP/1.1 200 OK` 响应。

你应该在 Kafka topic 中看到类似如下的日志条目：

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

将元日志格式更新为 `origin`：

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

再次向路由发送请求以生成新的日志条目：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该收到一个 `HTTP/1.1 200 OK` 响应。

你应该在 Kafka topic 中看到类似如下的日志条目：

```text
GET /get HTTP/1.1
x-forwarded-proto: http
x-forwarded-host: 127.0.0.1
user-agent: curl/8.7.1
x-forwarded-port: 9080
host: 127.0.0.1:9080
accept: */*
```

### 通过插件元数据记录请求和响应头

以下示例演示了如何使用[插件元数据](../terminology/plugin-metadata.md)和[内置变量](../apisix-variable.md)自定义日志格式，以记录请求和响应中的特定头字段。

插件元数据用于配置同一插件的所有插件实例的公共元数据字段，当一个插件在多个资源上启用且需要统一更新其元数据字段时非常有用。

首先，创建一条启用 `kafka-logger` 插件的路由。将 `meta_format` 设置为 `default`（使用插件元数据自定义日志格式时必须设置），并将 `batch_max_size` 设置为 `1` 以立即发送日志条目：

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
            "host": "kafka",
            "port": 29092
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

如果 `meta_format` 设置为 `origin`，无论插件元数据中的日志格式配置如何，日志条目都将保持 `origin` 格式。

:::

接下来，为 `kafka-logger` 配置插件元数据，以记录自定义请求头 `env` 和响应头 `Content-Type`：

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

向路由发送带有 `env` 头的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "env: dev"
```

你应该在 Kafka topic 中看到类似如下的日志条目：

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

### 按条件记录请求体

以下示例演示了如何有条件地记录请求体。

创建一条启用 `kafka-logger` 插件的路由。将 `include_req_body` 设置为 `true` 以包含请求体，并设置 `include_req_body_expr`，使其仅在 URL 查询字符串 `log_body` 等于 `yes` 时才包含请求体：

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
            "host": "kafka",
            "port": 29092
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

发送满足条件的请求（包含查询字符串）：

```shell
curl -i "http://127.0.0.1:9080/post?log_body=yes" -X POST -d '{"env": "dev"}'
```

你应该看到请求体被记录到日志中：

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

发送不包含查询字符串的请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -d '{"env": "dev"}'
```

此时日志中不会包含请求体。

:::note

如果在将 `include_req_body` 或 `include_resp_body` 设置为 `true` 的同时自定义了 `log_format`，插件将不会在日志中包含请求体或响应体。作为变通方案，可以在日志格式中使用 NGINX 变量 `$request_body`：

```json
{
  "kafka-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
