---
title: clickhouse-logger
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

## 目录

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**如何开启**](#如何开启)
- [**测试插件**](#测试插件)
- [**插件元数据设置**](#插件元数据设置)
- [**禁用插件**](#禁用插件)

## 定义

`clickhouse-logger` 是一个插件，可将Log数据请求推送到clickhouse服务器。

## 属性列表

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| endpoint_addr    | string  | 必须   |               |         | `clickhouse` 服务器的 endpoint。                   |
| database         | string  | 必须   |               |         | 使用的数据库。                                    |
| logtable         | string  | 必须   |               |         | 写入的表名 。    |
| user             | string  | 必须   |               |         | clickhouse的用户。 |
| password         | string  | 必须   |               |         | clickhouse的密码 。  |
| timeout          | integer | 可选   | 3             | [1,...] | 发送请求后保持连接活动的时间。                   |
| name             | string  | 可选   | "clickhouse logger" |         | 标识 logger 的唯一标识符。                     |
| batch_max_size   | integer | 可选   | 100           | [1,...] | 设置每批发送日志的最大条数，当日志条数达到设置的最大值时，会自动推送全部日志到 `clickhouse` 。 |
| max_retry_count  | integer | 可选   | 0             | [0,...] | 从处理管道中移除之前的最大重试次数。               |
| retry_delay      | integer | 可选   | 1             | [0,...] | 如果执行失败，则应延迟执行流程的秒数。             |
| ssl_verify       | boolean | 可选   | true          | [true,false] | 验证证书。             |

## 如何开启

这是有关如何为特定路由启用 `clickhouse-logger` 插件的示例。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "clickhouse-logger": {
                "user": "default",
                "password": "a",
                "database": "default",
                "logtable": "test",
                "endpoint_addr": "http://127.0.0.1:8123"
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

## 测试插件

> 成功:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../../../en/latest/apisix-variable.md)或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 http-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/clickhouse-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

创建clickhouse log table

```sql
CREATE TABLE default.test (
  `host` String,
  `client_ip` String,
  `route_id` String,
  `@timestamp` String,
   PRIMARY KEY(`@timestamp`)
) ENGINE = MergeTree()
```

在clickhouse上执行`select * from default.test;`，将得到类似下面的数据：

```
┌─host──────┬─client_ip─┬─route_id─┬─@timestamp────────────────┐
│ 127.0.0.1 │ 127.0.0.1 │ 1        │ 2022-01-17T10:03:10+08:00 │
└───────────┴───────────┴──────────┴───────────────────────────┘
```

## 禁用插件

在插件配置中删除相应的 json 配置以禁用 clickhouse-logger。APISIX 插件是热重载的，因此无需重新启动 APISIX：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
