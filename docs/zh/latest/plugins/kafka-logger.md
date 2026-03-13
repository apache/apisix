---
title: kafka-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Kafka Logger
description: API 网关 Apache APISIX 的 kafka-logger 插件用于将日志作为 JSON 对象推送到 Apache Kafka 集群中。
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

## 描述

`kafka-logger` 插件用于将日志作为 JSON 对象推送到 Apache Kafka 集群中。可用作 `ngx_lua` NGINX 模块的 Kafka 客户端驱动程序。

## 属性

| 名称                   | 类型    | 必选项 | 默认值          | 有效值                | 描述                                             |
| ---------------------- | ------- | ------ | -------------- | --------------------- | ------------------------------------------------ |
| broker_list            | object  | 是     |                |                       | 已废弃，现使用 `brokers` 属性代替。原指需要推送的 Kafka 的 broker 列表。                  |
| brokers                | array   | 是     |                |                       | 需要推送的 Kafka 的 broker 列表。                   |
| brokers.host           | string  | 是     |                |                       | Kafka broker 的节点 host 配置，例如 `192.168.1.1`                     |
| brokers.port           | string  | 是     |                |                       | Kafka broker 的节点端口配置                         |
| brokers.sasl_config    | object  | 否     |                |                       | Kafka broker 中的 sasl_config                     |
| brokers.sasl_config.mechanism  | string  | 否     | "PLAIN"          | ["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"]   | Kafka broker 中的 sasl 认证机制                     |
| brokers.sasl_config.user       | string  | 是     |                  |             | Kafka broker 中 sasl 配置中的 user，如果 sasl_config 存在，则必须填写                 |
| brokers.sasl_config.password   | string  | 是     |                  |             | Kafka broker 中 sasl 配置中的 password，如果 sasl_config 存在，则必须填写             |
| kafka_topic            | string  | 是     |                |                       | 需要推送的 topic。                                 |
| producer_type          | string  | 否     | async          | ["async", "sync"]     | 生产者发送消息的模式。          |
| required_acks          | integer | 否     | 1              | [1, -1]            | 生产者在确认一个请求发送完成之前需要收到的反馈信息的数量。该参数是为了保证发送请求的可靠性。该属性的配置与 Kafka `acks` 属性相同，具体配置请参考 [Apache Kafka 文档](https://kafka.apache.org/documentation/#producerconfigs_acks)。required_acks 还不支持为 0。  |
| key                    | string  | 否     |                |                       | 用于消息分区而分配的密钥。                             |
| timeout                | integer | 否     | 3              | [1,...]               | 发送数据的超时时间。                             |
| name                   | string  | 否     | "kafka logger" |                       | 标识 logger 的唯一标识符。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。                     |
| meta_format            | enum    | 否     | "default"      | ["default"，"origin"] | `default`：获取请求信息以默认的 JSON 编码方式。`origin`：获取请求信息以 HTTP 原始请求方式。更多信息，请参考 [meta_format](#meta_format-示例)。|
| log_format             | object  | 否   | |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body       | boolean | 否     | false          | [false, true]         | 当设置为 `true` 时，包含请求体。**注意**：如果请求体无法完全存放在内存中，由于 NGINX 的限制，APISIX 无法将它记录下来。|
| include_req_body_expr  | array   | 否     |                |                       | 当 `include_req_body` 属性设置为 `true` 时进行过滤。只有当此处设置的表达式计算结果为 `true` 时，才会记录请求体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| max_req_body_bytes     | integer | 否    | 524288         | >=1                   | 允许的最大请求正文（以字节为单位）。在此限制内的请求体将被推送到 Kafka。如果大小超过配置值，则正文在推送到 Kafka 之前将被截断。                                                                                                                                                                                                  |
| include_resp_body      | boolean | 否     | false          | [false, true]         | 当设置为 `true` 时，包含响应体。 |
| include_resp_body_expr | array   | 否     |                |                       | 当 `include_resp_body` 属性设置为 `true` 时进行过滤。只有当此处设置的表达式计算结果为 `true` 时才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。|
| max_resp_body_bytes    | integer | 否    | 524288         | >=1                   | 允许的最大响应正文（以字节为单位）。低于此限制的响应主体将被推送到 Kafka。如果大小超过配置值，则正文在推送到 Kafka 之前将被截断。                                                                                                                                                                                                  |
| cluster_name           | integer | 否     | 1              | [0,...]               | Kafka 集群的名称，当有两个及以上 Kafka 集群时使用。只有当 `producer_type` 设为 `async` 模式时才可以使用该属性。|
| producer_batch_num     | integer | 否     | 200            | [1,...]               | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `batch_num` 参数，聚合消息批量提交，单位为消息条数。 |
| producer_batch_size    | integer | 否     | 1048576        | [0,...]               | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `batch_size` 参数，单位为字节。 |
| producer_max_buffering | integer | 否     | 50000          | [1,...]               | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `max_buffering` 参数，表示最大缓冲区，单位为条。 |
| producer_time_linger   | integer | 否     | 1              | [1,...]               | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `flush_time` 参数，单位为秒。|
| meta_refresh_interval | integer  | 否     | 30             | [1,...]               | 对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `refresh_interval` 参数，用于指定自动刷新 metadata 的间隔时长，单位为秒。 |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

:::tip 提示

数据首先写入缓冲区。当缓冲区超过 `batch_max_size` 或 `buffer_duration` 设置的值时，则会将数据发送到 Kafka 服务器并刷新缓冲区。

如果发送成功，则返回 `true`。如果出现错误，则返回 `nil`，并带有描述错误的字符串 `buffer overflow`。

:::

### meta_format 示例

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

## 插件元数据

| 名称             | 类型    | 必选项 | 默认值        |  描述                                             |
| ---------------- | ------- | ------ | ------------- |------------------------------------------------ |
| log_format       | object  | 否   |   | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::note 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `kafka-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/kafka-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

配置完成后，你将在日志系统中看到如下类似日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## 如何启用

你可以通过如下命令在指定路由上启用 `kafka-logger` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "kafka-logger": {
            "brokers" : [
              {
               "host": "127.0.0.1",
               "port": 9092
              }
            ],
           "kafka_topic" : "test2",
           "key" : "key1"
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

该插件还支持一次推送到多个 Broker，示例如下：

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

## 测试插件

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
