---
title: error-log-logger
keywords:
  - APISIX
  - API 网关
  - 错误日志
  - Plugin
description: API 网关 Apache APISIX error-log-logger 插件用于将 APISIX 的错误日志推送到 TCP、Apache SkyWalking 或 ClickHouse 服务器。
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

`error-log-logger` 插件用于将 APISIX 的错误日志 (`error.log`) 推送到 TCP、Apache SkyWalking 或 ClickHouse 服务器，你还可以设置错误日志级别以将日志发送到服务器。

## 属性

| 名称                              | 类型    | 必选项 | 默认值                         | 有效值         | 描述                                                                             |
| -------------------------------- | ------- | ------ | ------------------------------ | ------------- | -------------------------------------------------------------------------------- |
| tcp.host                         | string  | 是     |                                |               | TCP 服务的 IP 地址或主机名。                                                      |
| tcp.port                         | integer | 是     |                                | [0,...]       | 目标端口。                                                                        |
| tcp.tls                          | boolean | 否     | false                          | [false, true] | 当设置为 `true` 时执行 SSL 验证。                                                |
| tcp.tls_server_name              | string  | 否     |                                |               | TLS 服务名称标记。                                                                 |
| skywalking.endpoint_addr         | string  | 否     | http://127.0.0.1:12900/v3/logs |               | SkyWalking 的 HTTP endpoint 地址，例如：http://127.0.0.1:12800。                   |
| skywalking.service_name          | string  | 否     | APISIX                         |               | SkyWalking 上报的 service 名称。                                                   |
| skywalking.service_instance_name | String  | 否     | APISIX Instance Name           |               | SkyWalking 上报的 service 实例名，如果希望直接获取本机主机名请设置为 `$hostname`。   |
| clickhouse.endpoint_addr         | String  | 否     | http://127.0.0.1:8213          |               | ClickHouse 的 HTTP endpoint 地址，例如 `http://127.0.0.1:8213`。                   |
| clickhouse.user                  | String  | 否     | default                        |               | ClickHouse 的用户名。                                                              |
| clickhouse.password              | String  | 否     |                                |               | ClickHouse 的密码。                                                                |
| clickhouse.database              | String  | 否     |                                |               | ClickHouse 的用于接收日志的数据库。                                                |
| clickhouse.logtable              | String  | 否     |                                |               | ClickHouse 的用于接收日志的表。                                                    |
| timeout                          | integer | 否     | 3                              | [1,...]       | 连接和发送数据超时间，以秒为单位。                                                   |
| keepalive                        | integer | 否     | 30                             | [1,...]       | 复用连接时，连接保持的时间，以秒为单位。                                             |
| level                            | string  | 否     | WARN                           |               | 进行错误日志筛选的级别，默认为 `WARN`，取值 ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"]，其中 `ERR` 与 `ERROR` 级别一致。 |

注意：schema 中还定义了 `encrypt_fields = {"clickhouse.password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 启用插件

该插件默认为禁用状态，你可以在 `./conf/config.yaml` 中启用 `error-log-logger` 插件。你可以参考如下示例启用插件：

```yaml title=“./conf/config.yaml”
plugins:                          # plugin list
  ......
  - request-id
  - hmac-auth
  - api-breaker
  - error-log-logger              # enable plugin `error-log-logger
```

完成插件配置后，你需要重新加载 APISIX，插件才会生效。

:::note 注意

该插件属于 APISIX 全局性插件，不需要在任何路由或服务中绑定。

:::

### 配置 TCP 服务器地址

你可以通过配置插件元数据来设置 TCP 服务器地址，如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "tcp": {
    "host": "127.0.0.1",
    "port": 1999
  },
  "inactive_timeout": 1
}'
```

### 配置 SkyWalking OAP 服务器地址

通过以下配置插件元数据设置 SkyWalking OAP 服务器地址，如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "skywalking": {
    "endpoint_addr": "http://127.0.0.1:12800/v3/logs"
  },
  "inactive_timeout": 1
}'
```

### 配置 ClickHouse 数据库

该插件支持将错误日志作为字符串发送到 ClickHouse 服务器中对应表的 `data` 字段。

你可以按照如下方式进行配置：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-log-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## 禁用插件

当你不再需要该插件时，只需要在 `./conf/config.yaml` 中删除或注释该插件即可。

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  #- error-log-logger              # enable plugin `error-log-logger
```
