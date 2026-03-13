---
title: rocketmq-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - RocketMQ
description: API 网关 Apache APISIX 的 rocketmq-logger 插件用于将日志作为 JSON 对象推送到 Apache RocketMQ 集群中。
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

`rocketmq-logger` 插件可以将日志以 JSON 的形式推送给外部 RocketMQ 集群。

## 属性

| 名称                   | 类型     | 必选项 | 默认值            | 有效值                 | 描述                                              |
| ---------------------- | ------- | ------ | ----------------  | ------------- ------- | ------------------------------------------------ |
| nameserver_list        | object  | 是     |                   |                       | RocketMQ 的 nameserver 列表。                     |
| topic                  | string  | 是     |                   |                       | 要推送的 topic 名称。                             |
| key                    | string  | 否     |                   |                       | 发送消息的 keys。                                 |
| tag                    | string  | 否     |                   |                       | 发送消息的 tags。                                 |
| log_format             | object  | 否     |                   |                       | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| timeout                | integer | 否     | 3                 | [1,...]               | 发送数据的超时时间。                              |
| use_tls                | boolean | 否     | false             |                       | 当设置为 `true` 时，开启 TLS 加密。               |
| access_key             | string  | 否     | ""                |                       | ACL 认证的 Access key，空字符串表示不开启 ACL。    |
| secret_key             | string  | 否     | ""                |                       | ACL 认证的 Secret key。                           |
| name                   | string  | 否     | "rocketmq logger" |                       | 标识 logger 的唯一标识符。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。               |
| meta_format            | enum    | 否     | "default"         | ["default"，"origin"] | `default`：获取请求信息以默认的 JSON 编码方式。`origin`：获取请求信息以 HTTP 原始请求方式。更多信息，请参考 [meta_format](#meta_format-示例)。|
| include_req_body       | boolean | 否     | false             | [false, true]         | 当设置为 `true` 时，包含请求体。**注意**：如果请求体无法完全存放在内存中，由于 NGINX 的限制，APISIX 无法将它记录下来。|
| include_req_body_expr  | array   | 否     |                   |                       | 当 `include_req_body` 属性设置为 `true` 时进行过滤请求体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录请求体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| include_resp_body      | boolean | 否     | false             | [false, true]         | 当设置为 `true` 时，包含响应体。 |
| include_resp_body_expr | array   | 否     |                   |                       | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

:::tip 提示

数据首先写入缓冲区。当缓冲区超过 `batch_max_size` 或 `buffer_duration` 设置的值时，则会将数据发送到 RocketMQ 服务器并刷新缓冲区。

如果发送成功，则返回 `true`。如果出现错误，则返回 `nil`，并带有描述错误的字符串 `buffer overflow`。

:::

### meta_format 示例

- default:

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

- origin:

```http
    GET /hello?ab=cd HTTP/1.1
    host: localhost
    content-length: 6
    connection: close

    abcdef
```

## 插件元数据设置

| 名称         | 类型     | 必选项 | 默认值                                                                           | 描述                                                                                                                                                               |
|------------|--------|-----|-------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | 否   |  | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::note 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `rocketmq-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/rocketmq-logger \
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

在日志收集处，将得到类似下面的日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## 启用插件

你可以通过如下命令在指定路由上启用 `rocketmq-logger` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "rocketmq-logger": {
           "nameserver_list" : [ "127.0.0.1:9876" ],
           "topic" : "test2",
           "batch_max_size": 1,
           "name": "rocketmq logger"
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

该插件还支持一次推送到多个 `nameserver`，示例如下：

```json
[
    "127.0.0.1:9876",
    "127.0.0.2:9876"
]
```

## 测试插件

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
