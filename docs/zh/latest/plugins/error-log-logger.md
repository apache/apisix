---
title: error-log-logger
keywords:
  - APISIX
  - API 网关
  - 错误日志
  - Plugin
description: error-log-logger 插件将 APISIX 的错误日志批量推送到 TCP、Apache SkyWalking、Apache Kafka 或 ClickHouse 服务器，并支持指定日志级别进行过滤。
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

## 描述

`error-log-logger` 插件将 APISIX 的错误日志（`error.log`）批量推送到 TCP、[Apache SkyWalking](https://skywalking.apache.org/)、Apache Kafka 或 ClickHouse 服务器。你可以指定日志级别，插件只发送符合条件的日志。

该插件默认为禁用状态。启用后，插件会自动开始将错误日志推送到远端服务器。你只需在插件元数据中配置远端服务器的详细信息，无需在路由等其他资源上进行配置。

## 插件元数据

该插件没有路由或服务级别的属性，所有配置均通过插件元数据完成。

| 名称                                    | 类型    | 必选项 | 默认值                         | 有效值                                                                                  | 描述                                                                                                                                                           |
| --------------------------------------- | ------- | ------ | ------------------------------ | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| tcp                                     | object  | 否     |                                |                                                                                         | TCP 服务器配置。                                                                                                                                               |
| tcp.host                                | string  | 是     |                                |                                                                                         | TCP 服务器的 IP 地址或主机名。                                                                                                                                 |
| tcp.port                                | integer | 是     |                                | [0,...]                                                                                 | 目标端口。                                                                                                                                                     |
| tcp.tls                                 | boolean | 否     | false                          |                                                                                         | 设置为 `true` 时启用 SSL 验证。                                                                                                                                |
| tcp.tls_server_name                     | string  | 否     |                                |                                                                                         | TLS 服务名称标记（SNI）。                                                                                                                                      |
| skywalking                              | object  | 否     |                                |                                                                                         | SkyWalking 服务器配置。                                                                                                                                        |
| skywalking.endpoint_addr                | string  | 否     | http://127.0.0.1:12900/v3/logs |                                                                                         | SkyWalking 服务器的地址。                                                                                                                                      |
| skywalking.service_name                 | string  | 否     | APISIX                         |                                                                                         | SkyWalking 上报的服务名称。                                                                                                                                    |
| skywalking.service_instance_name        | string  | 否     | APISIX Instance Name           |                                                                                         | SkyWalking 上报的服务实例名称。设置为 `$hostname` 可直接获取本机主机名。                                                                                       |
| clickhouse                              | object  | 否     |                                |                                                                                         | ClickHouse 服务器配置。                                                                                                                                        |
| clickhouse.endpoint_addr                | string  | 否     | http://127.0.0.1:8123          |                                                                                         | ClickHouse 的 HTTP endpoint 地址。                                                                                                                             |
| clickhouse.user                         | string  | 否     | default                        |                                                                                         | ClickHouse 用户名。                                                                                                                                            |
| clickhouse.password                     | string  | 否     |                                |                                                                                         | ClickHouse 密码。密码在存入 etcd 前会经过 AES 加密。详见[加密存储字段](../plugin-develop.md#加密存储字段)。                                                    |
| clickhouse.database                     | string  | 否     |                                |                                                                                         | 用于存储日志的数据库名称。                                                                                                                                     |
| clickhouse.logtable                     | string  | 否     |                                |                                                                                         | 用于存储日志的表名称。该表需包含 `data` 列，插件将日志推送至该列。                                                                                             |
| kafka                                   | object  | 否     |                                |                                                                                         | Kafka 服务器配置。                                                                                                                                             |
| kafka.brokers                           | array   | 是     |                                |                                                                                         | Kafka broker 节点列表。                                                                                                                                        |
| kafka.brokers[].host                    | string  | 是     |                                |                                                                                         | Kafka broker 的主机地址。                                                                                                                                      |
| kafka.brokers[].port                    | integer | 是     |                                | [0, 65535]                                                                              | Kafka broker 的端口号。                                                                                                                                        |
| kafka.brokers[].sasl_config             | object  | 否     |                                |                                                                                         | Kafka broker 的 SASL 配置。                                                                                                                                    |
| kafka.brokers[].sasl_config.mechanism   | string  | 否     | PLAIN                          | ["PLAIN"]                                                                               | SASL 认证机制。                                                                                                                                                |
| kafka.brokers[].sasl_config.user        | string  | 是     |                                |                                                                                         | SASL 配置的用户名。当 `sasl_config` 存在时为必填。                                                                                                             |
| kafka.brokers[].sasl_config.password    | string  | 是     |                                |                                                                                         | SASL 配置的密码。当 `sasl_config` 存在时为必填。                                                                                                               |
| kafka.kafka_topic                       | string  | 是     |                                |                                                                                         | 推送日志的目标 topic。                                                                                                                                         |
| kafka.producer_type                     | string  | 否     | async                          | ["async", "sync"]                                                                       | 生产者发送消息的模式。                                                                                                                                         |
| kafka.required_acks                     | integer | 否     | 1                              | [-1, 0, 1]                                                                              | 生产者确认请求完成所需的 ack 数量。详见 [Apache Kafka 文档](https://kafka.apache.org/documentation/#producerconfigs_acks)。                                     |
| kafka.key                               | string  | 否     |                                |                                                                                         | 用于消息分区的键。                                                                                                                                             |
| kafka.cluster_name                      | integer | 否     | 1                              | [0,...]                                                                                 | 集群名称，当存在两个及以上 Kafka 集群时使用。仅在 `producer_type` 为 `async` 时有效。                                                                          |
| kafka.meta_refresh_interval             | integer | 否     | 30                             | [1,...]                                                                                 | 自动刷新 metadata 的时间间隔，单位为秒。对应 [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) 中的 `refresh_interval` 参数。                   |
| timeout                                 | integer | 否     | 3                              | [1,...]                                                                                 | 连接和发送数据的超时时间，单位为秒。                                                                                                                           |
| keepalive                               | integer | 否     | 30                             | [1,...]                                                                                 | 发送数据后保持连接的时间，单位为秒。                                                                                                                           |
| level                                   | string  | 否     | WARN                           | ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"] | 过滤错误日志的严重级别。`ERR` 与 `ERROR` 级别一致。                                                                                                           |
| name                                    | string  | 否     | error-log-logger               |                                                                                         | 批处理器中插件的唯一标识符。                                                                                                                                   |
| batch_max_size                          | integer | 否     | 1000                           | [1,...]                                                                                 | 每个批次允许的最大日志条目数。达到后立即发送批次。设置为 `1` 表示立即处理。                                                                                    |
| inactive_timeout                        | integer | 否     | 5                              | [1,...]                                                                                 | 等待新日志的最长时间（秒），超过则发送批次。该值应小于 `buffer_duration`。                                                                                     |
| buffer_duration                         | integer | 否     | 60                             | [1,...]                                                                                 | 从最早条目起允许的最长缓冲时间（秒），超过则发送批次。                                                                                                         |
| retry_delay                             | integer | 否     | 1                              | [0,...]                                                                                 | 批次发送失败后重试的时间间隔，单位为秒。                                                                                                                       |
| max_retry_count                         | integer | 否     | 60                             | [0,...]                                                                                 | 丢弃日志条目前允许的最大重试次数。                                                                                                                             |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据），避免频繁提交数据。默认情况下，批处理器每 `5` 秒或队列中数据达到 `1000` 条时提交一次。详情及自定义配置请参考[批处理器](../batch-processor.md#配置)。

### 默认日志格式示例

```text
["2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:205: load(): new plugins: {"error-log-logger":true}, context: init_worker_by_lua*","\n","2024/01/06 16:04:30 [warn] 11786#9692271: *1 [lua] plugin.lua:255: load_stream(): new plugins: {"limit-conn":true,"ip-restriction":true,"syslog":true,"mqtt-proxy":true}, context: init_worker_by_lua*","\n"]
```

## 启用插件

`error-log-logger` 插件默认为禁用状态。如需启用，请在配置文件（`conf/config.yaml`）中添加该插件：

```yaml title="conf/config.yaml"
plugins:
  - ...
  - error-log-logger
```

重新加载 APISIX 使更改生效。

启用插件后，通过插件元数据进行配置，示例见下文。

## 使用示例

以下示例演示了 `error-log-logger` 插件在不同场景下的配置方式。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 发送日志到 TCP 服务器

以下示例演示如何配置 `error-log-logger` 插件将错误日志发送到 TCP 服务器。

启动一个监听 `19000` 端口的 TCP 服务器：

```shell
nc -l 19000
```

配置插件元数据，设置 TCP 服务器的主机和端口，并将日志级别设为 `INFO` 以便发送更多日志进行验证：

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

如需验证，可以通过重新加载 APISIX 手动生成一条 `warn` 级别的日志。在 netcat 监听的终端中，你应该看到类似以下的日志条目：

```text
2025/01/26 20:15:29 [warn] 211#211: *35552 [lua] plugin.lua:205: load(): new plugins: {...}, context: init_worker_by_lua*
```

### 发送日志到 SkyWalking

以下示例演示如何配置 `error-log-logger` 插件将错误日志发送到 SkyWalking。

参照 [SkyWalking 文档](https://skywalking.apache.org/docs/main/next/en/setup/backend/backend-docker/) 使用 Docker Compose 启动 SkyWalking 存储、OAP 和 Booster UI。完成后，OAP 服务器应在 `12800` 端口监听，你可以通过 [http://localhost:8080](http://localhost:8080) 访问 UI。

配置插件元数据，设置 SkyWalking endpoint 地址，并将日志级别设为 `INFO` 以便发送更多日志进行验证：

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

如需验证，可以通过重新加载 APISIX 手动生成一条 `warn` 级别的日志。在 SkyWalking UI 中，导航至**General Service** > **Services**，应看到名为 `APISIX` 的服务及其日志条目。

### 发送日志到 ClickHouse

以下示例演示如何配置 `error-log-logger` 插件将错误日志发送到 ClickHouse。

启动一个使用 `default` 用户和空密码的 ClickHouse 服务器：

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name clickhouse-server clickhouse/clickhouse-server
```

在 ClickHouse 的 `default` 数据库中，创建一个包含 `data` 列的 `default_logs` 表。插件会将日志推送到该列：

```shell
curl "http://127.0.0.1:8123" -X POST -d '
  CREATE TABLE default.default_logs (
    data String,
    PRIMARY KEY(`data`)
  )
  ENGINE = MergeTree()
' --user default:
```

配置插件元数据，填写 ClickHouse 服务器详情，并将日志级别设为 `INFO` 以便发送更多日志进行验证：

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

如需验证，可以通过重新加载 APISIX 手动生成一条 `warn` 级别的日志，然后向 ClickHouse 发送查询请求查看日志条目：

```shell
echo 'SELECT * FROM default.default_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

### 发送日志到 Kafka

以下示例演示如何配置 `error-log-logger` 插件将错误日志发送到 Kafka 服务器。

配置插件元数据，填写 Kafka broker 的详情：

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
