---
title: rocketmq-logger
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

`rocketmq-logger` 插件可以将接口请求日志以 JSON 的形式推送给外部 rocketmq 集群。

如果在短时间内没有收到日志数据，请放心，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考。
[Batch-Processor](../batch-processor.md)

## 属性

| 名称             | 类型    | 必选项 | 默认值         | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | -------------- | ------- | ------------------------------------------------ |
| nameserver_list  | object  | 必须   |                |         | 要推送的 rocketmq 的 nameserver 列表。        |
| topic            | string  | 必须   |                |         | 要推送的 topic 。                             |
| key              | string  | 可选   |                |         | 发送消息的 keys 。                             |
| tag              | string  | 可选   |                |         | 发送消息的 tags 。                             |
| timeout          | integer | 可选   | 3              | [1,...] | 发送数据的超时时间。                          |
| use_tls          | boolean | 可选   | false          |         | 是否开启 TLS 加密。                             |
| access_key       | string  | 可选   | ""             |         | ACL 认证的 access key ，空字符串表示不开启 ACL 。     |
| secret_key       | string  | 可选   | ""             |         | ACL 认证的 secret key 。                         |
| name             | string  | 可选   | "rocketmq logger" |         | batch processor 的唯一标识。               |
| meta_format      | enum    | 可选   | "default"      | ["default"，"origin"] | `default`：获取请求信息以默认的 JSON 编码方式。`origin`：获取请求信息以 HTTP 原始请求方式。[具体示例](#meta_format-参考示例)|
| include_req_body | boolean | 可选   | false          | [false, true] | 是否包括请求 body 。false ： 表示不包含请求的 body ；true ： 表示包含请求的 body 。注意：如果请求 body 没办法完全放在内存中，由于 Nginx 的限制，我们没有办法把它记录下来。|
| include_req_body_expr | array  | 可选    |           |         | 当 `include_req_body` 开启时，基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式的结果进行记录。如果该选项存在，只有在表达式为真的时候才会记录请求 body 。 |
| include_resp_body| boolean | 可选   | false          | [false, true] | 是否包括响应体。包含响应体，当为 `true` 。 |
| include_resp_body_expr | array  | 可选    |           |         | 是否采集响体，基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 该选项需要开启 `include_resp_body` |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

### meta_format 参考示例

- **default**:

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

- **origin**:

```http
    GET /hello?ab=cd HTTP/1.1
    host: localhost
    content-length: 6
    connection: close

    abcdef
```

## 工作原理

消息将首先写入缓冲区。
当缓冲区超过 `batch_max_size` 时，它将发送到 rocketmq 服务器，
或每个 `buffer_duration` 刷新缓冲区。

如果成功，则返回 `true` 。
如果出现错误，则返回 `nil` ，并带有描述错误的字符串（`buffer overflow`）。

### Nameserver 列表

配置多个 nameserver 地址如下：

```json
[
    "127.0.0.1:9876",
    "127.0.0.2:9876"
]
```

## 如何启用

1. 为特定路由启用 rocketmq-logger 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "rocketmq-logger": {
           "nameserver_list" : [ "127.0.0.1:9876" ],
           "topic" : "test2",
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

## 测试插件

成功

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。请注意，**该设置是全局生效的**，因此在指定 log_format 后，将对所有绑定 rocketmq-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/rocketmq-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

在日志收集处，将得到类似下面的日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 禁用插件

当您要禁用 `rocketmq-logger` 插件时，这很简单，您可以在插件配置中删除相应的 json 配置，无需重新启动服务，它将立即生效：

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
