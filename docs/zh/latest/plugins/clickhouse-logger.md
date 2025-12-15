---
title: clickhouse-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - ClickHouse
description: 本文介绍了 API 网关 Apache APISIX 如何使用 clickhouse-logger 插件将日志数据发送到 ClickHouse 数据库中。
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

`clickhouse-logger` 插件可用于将日志数据推送到 [ClickHouse](https://github.com/ClickHouse/ClickHouse) 数据库中。

## 属性

| 名称             | 类型    | 必选项  | 默认值              | 有效值       | 描述                                                     |
| ---------------- | ------- | ------ | ------------------- | ----------- | -------------------------------------------------------- |
| endpoint_addr    | 废弃    | 是     |                     |              | ClickHouse 的 `endpoints`。请使用 `endpoint_addrs` 代替。 |
| endpoint_addrs   | array   | 是     |                     |              | ClickHouse 的 `endpoints。`。                            |
| database         | string  | 是     |                     |              | 使用的数据库。                                            |
| logtable         | string  | 是     |                     |              | 写入的表名。                                              |
| user             | string  | 是     |                     |              | ClickHouse 的用户。                                       |
| password         | string  | 是     |                     |              | ClickHouse 的密码。                                      |
| timeout          | integer | 否     | 3                   | [1,...]      | 发送请求后保持连接活动的时间。                             |
| name             | string  | 否     | "clickhouse logger" |              | 标识 logger 的唯一标识符。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。                               |
| ssl_verify       | boolean | 否     | true                | [true,false] | 当设置为 `true` 时，验证证书。                                                |
| log_format             | object  | 否   |          |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body       | boolean | 否     | false          | [false, true]         | 当设置为 `true` 时，包含请求体。**注意**：如果请求体无法完全存放在内存中，由于 NGINX 的限制，APISIX 无法将它记录下来。|
| include_req_body_expr  | array   | 否     |                |                       | 当 `include_req_body` 属性设置为 `true` 时进行过滤。只有当此处设置的表达式计算结果为 `true` 时，才会记录请求体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| include_resp_body      | boolean | 否     | false          | [false, true]         | 当设置为 `true` 时，包含响应体。 |
| include_resp_body_expr | array   | 否     |                |                       | 当 `include_resp_body` 属性设置为 `true` 时进行过滤。只有当此处设置的表达式计算结果为 `true` 时才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。|

注意：schema 中还定义了 `encrypt_fields = {"password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

### 默认日志格式示例

```json
{
    "response": {
        "status": 200,
        "size": 118,
        "headers": {
            "content-type": "text/plain",
            "connection": "close",
            "server": "APISIX/3.7.0",
            "content-length": "12"
        }
    },
    "client_ip": "127.0.0.1",
    "upstream_latency": 3,
    "apisix_latency": 98.999998092651,
    "upstream": "127.0.0.1:1982",
    "latency": 101.99999809265,
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "route_id": "1",
    "start_time": 1704507612177,
    "service_id": "",
    "request": {
        "method": "POST",
        "querystring": {
            "foo": "unknown"
        },
        "headers": {
            "host": "localhost",
            "connection": "close",
            "content-length": "18"
        },
        "size": 110,
        "uri": "/hello?foo=unknown",
        "url": "http://localhost:1984/hello?foo=unknown"
    }
}
```

## 配置插件元数据

`clickhouse-logger` 也支持自定义日志格式，与 [http-logger](./http-logger.md) 插件类似。

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否   |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX](../apisix-variable.md) 或 [NGINX](http://nginx.org/en/docs/varindex.html) 变量。该配置全局生效。如果你指定了 `log_format`，该配置就会对所有绑定 `clickhouse-logger` 的路由或服务生效。|
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/clickhouse-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

您可以使用 Clickhouse docker 镜像来创建一个容器，如下所示：

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name some-clickhouse-server --ulimit nofile=262144:262144 clickhouse/clickhouse-server
```

然后在您的 ClickHouse 数据库中创建一个表来存储日志。

```shell
curl -X POST 'http://localhost:8123/' \
--data-binary 'CREATE TABLE default.test (host String, client_ip String, route_id String, service_id String, `@timestamp` String, PRIMARY KEY(`@timestamp`)) ENGINE = MergeTree()' --user default:
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
      "plugins": {
            "clickhouse-logger": {
                "user": "default",
                "password": "",
                "database": "default",
                "logtable": "test",
                "endpoint_addrs": ["http://127.0.0.1:8123"]
            }
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

:::note 注意

如果配置多个 `endpoints`，日志将会随机写入到各个 `endpoints`。

:::

## 测试插件

现在你可以向 APISIX 发起请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

现在，如果您检查表中的行，您将获得以下输出：

```shell
curl 'http://localhost:8123/?query=select%20*%20from%20default.test'
127.0.0.1	127.0.0.1	1		2023-05-08T19:15:53+05:30
```

## 删除插件

当你需要删除该插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
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
