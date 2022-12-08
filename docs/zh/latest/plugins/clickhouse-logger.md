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
| password         | string  | 是     |                     |              | ClickHouse 的密码 。                                      |
| timeout          | integer | 否     | 3                   | [1,...]      | 发送请求后保持连接活动的时间。                             |
| name             | string  | 否     | "clickhouse logger" |              | 标识 logger 的唯一标识符。                                |
| ssl_verify       | boolean | 否     | true                | [true,false] | 当设置为 `true` 时，验证证书。                                                |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 配置插件元数据

`clickhouse-logger` 也支持自定义日志格式，与 [http-logger](./http-logger.md) 插件类似。

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX](../apisix-variable.md) 或 [NGINX](http://nginx.org/en/docs/varindex.html) 变量。该配置全局生效。如果你指定了 `log_format`，该配置就会对所有绑定 `clickhouse-logger` 的路由或服务生效。|

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/clickhouse-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

首先，你需要在 ClickHouse 数据库中创建一个表来存储日志：

```sql
CREATE TABLE default.test (
  `host` String,
  `client_ip` String,
  `route_id` String,
  `service_id` String,
  `@timestamp` String,
   PRIMARY KEY(`@timestamp`)
) ENGINE = MergeTree()
```

在 ClickHouse 中执行`select * from default.test;`，将得到类似下面的数据：

```
┌─host──────┬─client_ip─┬─route_id─┬─@timestamp────────────────┐
│ 127.0.0.1 │ 127.0.0.1 │ 1        │ 2022-01-17T10:03:10+08:00 │
└───────────┴───────────┴──────────┴───────────────────────────┘
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "clickhouse-logger": {
                "user": "default",
                "password": "a",
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

## 禁用插件

当你需要禁用该插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
