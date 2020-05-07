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

# Summary
- [**定义**](#name)
- [**属性列表**](#attributes)
- [**信息**](#info)
- [**如何开启**](#how-to-enable)
- [**测试插件**](#test-plugin)
- [**禁用插件**](#disable-plugin)

## 定义

`kafka-logger` 是一个插件，可用作ngx_lua nginx模块的Kafka客户端驱动程序。

这将提供将Log数据请求作为JSON对象发送到外部Kafka集群的功能。

该插件提供了将Log Data作为批处理推送到外部Kafka主题的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关Apache APISIX中Batch-Processor的更多信息，请参考。
[Batch-Processor](../batch-processor-cn.md)

## 属性列表

|属性名称          |必选项  |描述|
|---------     |--------|-----------|
| broker_list |必要的| 一系列的Kafka经纪人。|
| kafka_topic |必要的| 定位主题以推送数据。|
| timeout |可选的|上游发送数据超时。|
| async |可选的|布尔值，用于控制是否执行异步推送。|
| key |必要的|消息的密钥。|
| max_retry |可选的|没有重试次数。|

## 信息

异步与同步数据推送之间的区别。

1. 同步模型

    如果成功，则返回当前代理和分区的偏移量（** cdata：LL **）。
    如果发生错误，则返回“ nil”，并带有描述错误的字符串。

2. 在异步模型中

    消息将首先写入缓冲区。
    当缓冲区超过`batch_num`时，它将发送到kafka服务器，
    或每个`flush_time`刷新缓冲区。

    如果成功，则返回“ true”。
    如果出现错误，则返回“ nil”，并带有描述错误的字符串（“缓冲区溢出”）。

##### 样本经纪人名单

此插件支持一次推送到多个经纪人。如以下示例所示，指定外部kafka服务器的代理，以使此功能生效。

```json
{
    "127.0.0.1":9092,
    "127.0.0.1":9093
}
```

## 如何开启

1. 这是有关如何为特定路由启用kafka-logger插件的示例。

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
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
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
