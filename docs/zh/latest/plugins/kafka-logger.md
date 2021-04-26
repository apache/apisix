---
title: kafka-logger
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

- [**简介**](#简介)
- [**属性**](#属性)
- [**工作原理**](#工作原理)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 简介

`kafka-logger` 是一个插件，可用作ngx_lua nginx 模块的 Kafka 客户端驱动程序。

它可以将接口请求日志以 JSON 的形式推送给外部 Kafka 集群。如果在短时间内没有收到日志数据，请放心，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考。
[Batch-Processor](../batch-processor.md)

## 属性

| 名称             | 类型    | 必选项 | 默认值         | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | -------------- | ------- | ------------------------------------------------ |
| broker_list      | object  | 必须   |                |         | 要推送的 kafka 的 broker 列表。                  |
| kafka_topic      | string  | 必须   |                |         | 要推送的 topic。                                 |
| producer_type    | string  | 可选   | async          | ["async", "sync"]        | 生产者发送消息的模式。          |
| key              | string  | 可选   |                |         | 用于消息的分区分配。                             |
| timeout          | integer | 可选   | 3              | [1,...] | 发送数据的超时时间。                             |
| name             | string  | 可选   | "kafka logger" |         | batch processor 的唯一标识。                     |
| meta_format      | enum    | 可选   | "default"      | ["default"，"origin"] | `default`：获取请求信息以默认的 JSON 编码方式。`origin`：获取请求信息以 HTTP 原始请求方式。[具体示例](#meta_format-参考示例)|
| batch_max_size   | integer | 可选   | 1000           | [1,...] | 设置每批发送日志的最大条数，当日志条数达到设置的最大值时，会自动推送全部日志到 `Kafka` 服务。|
| inactive_timeout | integer | 可选   | 5              | [1,...] | 刷新缓冲区的最大时间（以秒为单位），当达到最大的刷新时间时，无论缓冲区中的日志数量是否达到设置的最大条数，也会自动将全部日志推送到 `Kafka` 服务。 |
| buffer_duration  | integer | 可选   | 60             | [1,...] | 必须先处理批次中最旧条目的最长期限（以秒为单位）。 |
| max_retry_count  | integer | 可选   | 0              | [0,...] | 从处理管道中移除之前的最大重试次数。             |
| retry_delay      | integer | 可选   | 1              | [0,...] | 如果执行失败，则应延迟执行流程的秒数。           |
| include_req_body | boolean | 可选   | false          | [false, true] | 是否包括请求 body。false： 表示不包含请求的 body ； true： 表示包含请求的 body 。|

### meta_format 参考示例

- **default**:

    ```json
    [
      {
        "client_ip": "127.0.0.1",
        "latency": 493.99995803833,
        "request": {
          "headers": {
            "accept": "*/*",
            "host": "httpbin.org",
            "user-agent": "curl/7.29.0"
          },
          "method": "GET",
          "querystring": {
            "foo1": "bar1",
            "foo2": "bar2"
          },
          "size": 98,
          "uri": "/get?foo1=bar1&foo2=bar2",
          "url": "http://httpbin.org:9080/get?  foo1=bar1&foo2=bar2"
        },
        "response": {
          "headers": {
            "access-control-allow-credentials":     "true",
            "access-control-allow-origin": "*",
            "connection": "close",
            "content-length": "370",
            "content-type": "application/json",
            "date": "Mon, 26 Apr 2021 02:03:27  GMT",
            "server": "APISIX/2.5"
          },
          "size": 595,
          "status": 200
        },
        "route_id": "5",
        "server": {
          "hostname": "localhost.localdomain",
          "version": "2.5"
        },
        "service_id": "",
        "start_time": 1619402607026,
        "upstream": "34.199.75.4:80"
      }
    ]
    ```

- **origin**:

    ```http
    GET /get?foo1=bar1&foo2=bar2 HTTP/1.1
    User-Agent: curl/7.29.0
    Accept: */*
    Host: httpbin.org

    HTTP/1.1 200 OK
    Content-Type: application/json
    Content-Length: 370
    Connection: keep-alive
    Date: Mon, 26 Apr 2021 02:03:31 GMT
    Access-Control-Allow-Origin: *
    Access-Control-Allow-Credentials: true
    Server: APISIX/2.5

    {
      "args": {
        "foo1": "bar1",
        "foo2": "bar2"
      },
      "headers": {
        "Accept": "*/*",
        "Host": "httpbin.org",
        "User-Agent": "curl/7.29.0",
        "X-Amzn-Trace-Id": "Root=1-60861f73-265a57f8445eff076c072f04",
        "X-Forwarded-Host": "httpbin.org"
      },
      "origin": "127.0.0.1, 129.227.137.235",
      "url": "http://httpbin.org/get?foo1=bar1&foo2=bar2"
    }
    ```

## 工作原理

消息将首先写入缓冲区。
当缓冲区超过`batch_max_size`时，它将发送到 kafka 服务器，
或每个`buffer_duration`刷新缓冲区。

如果成功，则返回 `true`。
如果出现错误，则返回 `nil`，并带有描述错误的字符串（`buffer overflow`）。

### Broker 列表

插件支持一次推送到多个 Broker，如下配置：

```json
{
    "127.0.0.1":9092,
    "127.0.0.1":9093
}
```

## 如何启用

1. 为特定路由启用 kafka-logger 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "kafka-logger": {
           "broker_list" :
             {
               "127.0.0.1":9092
             },
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

## 测试插件

 成功

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件

当您要禁用`kafka-logger`插件时，这很简单，您可以在插件配置中删除相应的 json 配置，无需重新启动服务，它将立即生效：

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
