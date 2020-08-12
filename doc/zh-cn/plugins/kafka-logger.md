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

- [English](../../plugins/kafka-logger.md)

# 目录
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

|属性名称          |必选项  |描述|
|---------     |--------|-----------|
| broker_list |必须| 要推送的 kafka 的 broker 列表。|
| kafka_topic |必须| 要推送的 topic。|
| timeout |可选| 发送数据的超时时间。|
| key |必须| 用于加密消息的密钥。|
| name |必须| batch processor 的唯一标识。|
| batch_max_size |可选| 批量发送的消息最大数量，当到达该阀值后会立即发送消息|
| inactive_timeout |可选| 不活跃时间，如果在该时间范围内都没有消息写入缓冲区，那么会立即发送到 kafka。默认值： 5(s)|
| buffer_duration |可选| 缓冲周期，消息停留在缓冲区的最大时间，当超过该时间时会立即发送到 kafka。默认值： 60(s)|
| max_retry_count |可选| 最大重试次数。默认值： 0|
| retry_delay |可选| 重试间隔。默认值： 1(s)|

## 工作原理

消息将首先写入缓冲区。
当缓冲区超过`batch_max_size`时，它将发送到kafka服务器，
或每个`buffer_duration`刷新缓冲区。

如果成功，则返回“ true”。
如果出现错误，则返回“ nil”，并带有描述错误的字符串（`buffer overflow`）。

##### Broker 列表

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

* 成功:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件

当您要禁用`kafka-logger`插件时，这很简单，您可以在插件配置中删除相应的json配置，无需重新启动服务，它将立即生效：

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
