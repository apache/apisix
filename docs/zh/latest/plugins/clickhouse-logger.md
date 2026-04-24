---
title: clickhouse-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - ClickHouse
description: clickhouse-logger 插件将请求和响应日志批量推送到 ClickHouse 数据库，并支持自定义日志格式以增强数据管理。
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

## 描述

`clickhouse-logger` 插件将请求和响应日志批量推送到 [ClickHouse](https://clickhouse.com/) 数据库，并支持自定义日志格式。

## 属性

| 名称                   | 类型        | 必选项 | 默认值              | 有效值         | 描述                                                                                                                                                                                                                                   |
|------------------------|-------------|--------|---------------------|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint_addrs         | array       | True   |                     |                | ClickHouse 的 endpoints。                                                                                                                                                                                                              |
| database               | string      | True   |                     |                | 存储日志的数据库名称。                                                                                                                                                                                                                 |
| logtable               | string      | True   |                     |                | 存储日志的表名称。                                                                                                                                                                                                                     |
| user                   | string      | True   |                     |                | ClickHouse 用户名。从 APISIX 3.16.0 开始，支持使用 `$ENV://` 前缀引用环境变量，或使用 `$secret://` 前缀引用密钥管理器中的值。详情参见 [secrets](../terminology/secret.md)。                                                            |
| password               | string      | True   |                     |                | ClickHouse 密码。从 APISIX 3.16.0 开始，支持使用 `$ENV://` 前缀引用环境变量，或使用 `$secret://` 前缀引用密钥管理器中的值。详情参见 [secrets](../terminology/secret.md)。                                                              |
| timeout                | integer     | False  | 3                   | 大于 0         | 发送请求后保持连接活跃的时间（秒）。                                                                                                                                                                                                   |
| ssl_verify             | boolean     | False  | true                |                | 若为 `true`，则验证 SSL 证书。                                                                                                                                                                                                         |
| log_format             | object      | False  |                     |                | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可通过[插件元数据](#插件元数据)全局配置日志格式。      |
| include_req_body       | boolean     | False  | false               |                | 若为 `true`，则在日志中包含请求体。注意：如果请求体太大无法保存在内存中，由于 NGINX 的限制将无法记录。                                                                                                                                  |
| include_req_body_expr  | array       | False  |                     |                | 当 `include_req_body` 为 `true` 时使用的过滤条件数组，以 [APISIX 表达式](https://github.com/api7/lua-resty-expr) 形式表示。仅当表达式求值为 `true` 时才记录请求体。                                                                   |
| include_resp_body      | boolean     | False  | false               |                | 若为 `true`，则在日志中包含响应体。                                                                                                                                                                                                    |
| include_resp_body_expr | array       | False  |                     |                | 当 `include_resp_body` 为 `true` 时使用的过滤条件数组，以 [APISIX 表达式](https://github.com/api7/lua-resty-expr) 形式表示。仅当表达式求值为 `true` 时才记录响应体。                                                                  |
| max_req_body_bytes     | integer     | False  | 524288              | >= 1           | 日志中包含的最大请求体大小（字节）。超出此值的请求体将被截断。APISIX 3.16.0 起可用。                                                                                                                                                   |
| max_resp_body_bytes    | integer     | False  | 524288              | >= 1           | 日志中包含的最大响应体大小（字节）。超出此值的响应体将被截断。APISIX 3.16.0 起可用。                                                                                                                                                   |
| name                   | string      | False  | "clickhouse logger" |                | 批处理器中插件的唯一标识符。如果使用 [Prometheus](./prometheus.md) 监控 APISIX 指标，该名称将在 `apisix_batch_process_entries` 中导出。                                                                                                 |
| batch_max_size         | integer     | False  | 1000                | 大于 0         | 单批允许的日志条目数。达到此数量后，批次将被发送至 ClickHouse。设置为 `1` 表示立即处理。                                                                                                                                               |
| inactive_timeout       | integer     | False  | 5                   | 大于 0         | 在发送批次到日志服务之前等待新日志的最长时间（秒）。该值应小于 `buffer_duration`。                                                                                                                                                     |
| buffer_duration        | integer     | False  | 60                  | 大于 0         | 在发送批次到日志服务之前，允许最早条目存在的最长时间（秒）。                                                                                                                                                                           |
| retry_delay            | integer     | False  | 1                   | >= 0           | 批次发送失败后重试的时间间隔（秒）。                                                                                                                                                                                                   |
| max_retry_count        | integer     | False  | 60                  | >= 0           | 在丢弃日志条目之前允许的最大重试次数。                                                                                                                                                                                                 |

注意：schema 中还定义了 `encrypt_fields = {"password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

此外，你可以使用环境变量或者 APISIX Secret 来存放和引用插件配置。详情参见 [secrets](../terminology/secret.md)。

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据。如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 插件元数据

| 名称               | 类型    | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                                                                                 |
|--------------------|---------|--------|--------|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False  |        |        | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。该配置全局生效，对所有绑定 `clickhouse-logger` 的路由和服务生效。 |
| max_pending_entries | integer | False |        | >= 1   | 批处理器中允许的最大未处理条目数。达到此限制后，新条目将被丢弃，直到积压减少。                                                                                                                         |

## 示例

以下示例演示了如何为不同场景配置 `clickhouse-logger` 插件。

按照示例操作，首先启动一个使用 `default` 用户和空密码的 ClickHouse 服务器：

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name clickhouse-server clickhouse/clickhouse-server
```

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用默认日志格式记录日志

以下示例演示如何使用默认日志格式记录请求日志。

在 ClickHouse 数据库中创建名为 `default_logs` 的表，列对应默认日志格式：

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
    server String, 
    PRIMARY KEY(`start_time`)
  )
  ENGINE = MergeTree()
  ORDER BY (start_time)
' --user default:
```

创建一条启用 `clickhouse-logger` 插件的路由：

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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该看到 `HTTP/1.1 200 OK` 响应。

向 ClickHouse 发送请求以查看日志条目：

```shell
echo 'SELECT * FROM default.default_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

您应该看到类似如下的日志条目：

```text
┏━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━┓
┃ host ┃ client_ip  ┃ route_id                ┃ service_id ┃ start_time    ┃ latency         ┃ upstream_latency ┃ apisix_latency  ┃ consumer ┃ request ┃ response ┃ server  ┃
┡━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━┩
│      │ 172.19.0.1 │ clickhouse-logger-route │            │ 1703026935235 │ 481.00018501282 │ 473              │ 8.0001850128174 │          │ {...}   │ {...}    │ {...}   │
└──────┴────────────┴─────────────────────────┴────────────┴───────────────┴─────────────────┴──────────────────┴─────────────────┴──────────┴─────────┴──────────┴─────────┘
```

### 使用插件元数据自定义日志格式

以下示例演示如何使用插件元数据和 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) 自定义日志格式。

插件元数据全局生效，对所有 `clickhouse-logger` 实例有效。如果单个插件实例上配置的日志格式与插件元数据中配置的日志格式不同，则实例级别的配置优先。

在 ClickHouse 数据库中创建名为 `custom_logs` 的表，列对应自定义日志格式：

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
' --user default:
```

创建一条启用 `clickhouse-logger` 插件的路由：

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

为 `clickhouse-logger` 配置插件元数据：

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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该看到 `HTTP/1.1 200 OK` 响应。

向 ClickHouse 发送请求以查看日志条目：

```shell
echo 'SELECT * FROM default.custom_logs FORMAT Pretty' | curl "http://127.0.0.1:8123/?" -d @-
```

您应该看到类似如下的日志条目：

```text
┏━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ host      ┃ client_ip  ┃ route_id                ┃ service_id ┃ @timestamp                ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ 127.0.0.1 │ 172.19.0.1 │ clickhouse-logger-route │            │ 2023-12-19T23:25:43+00:00 │
└───────────┴────────────┴─────────────────────────┴────────────┴───────────────────────────┘
```
