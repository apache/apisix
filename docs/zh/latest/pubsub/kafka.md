---
title: Apache Kafka
keywords:
  - APISIX
  - Pub-Sub
  - Kafka
description: This document contains information about the Apache APISIX kafka pub-sub scenario.
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

## 连接至 Apache Kafka

在 Apache APISIX 中连接 Apache Kafka 非常简单。

当前我们实现的功能较为简单，可以实现获取偏移量（ListOffsets）、获取消息（Fetch）的功能，暂不支持 Apache Kafka 的消费者组功能，无法由 Kafka 管理偏移量。

### 局限性

- 用户需要手动管理偏移量：可以由自定义后端服务存储，或在开始获取消息前通过 List Offset 命令获取，它可以使用时间戳获取起始偏移量，或是获取初始、末尾偏移量。
- 单条指令仅可获取一个 Topic Partition 的数据：暂不支持通过单条指令批量获取数据

### 准备

首先，需要使用 `protoc` 将[通信协议](../../../../apisix/pubsub.proto)编译为特定语言 SDK，它提供指令和响应定义，即可通过 APISIX 以 WebSocket 连接至 Kafka。

协议中 `sequence` 字段用来关联请求与响应，它们将一一对应，客户端可以以自己需要的方式管理它，APISIX 将不会对其进行修改，仅通过响应体透传回客户端。

当前 Apache Kafka 使用以下指令：这些指令都是针对某个特定的 Topic 和 Partition，暂不支持

- CmdKafkaFetch
- CmdKafkaListOffset

> `CmdKafkaListOffset` 指令中的 `timestamp` 字段支持以下情况：
>
> - 时间戳：获取指定时间戳后的首条消息偏移量
> - `-1`：当前 Partition 最后一条消息偏移量
> - `-2`：当前 Partition 首条消息偏移量
>
> 更多信息参考 [Apache Kafka 协议文档](https://kafka.apache.org/protocol.html#The_Messages_ListOffsets)

可能的响应体：当出现错误时，将返回 `ErrorResp`，它包括错误字符串；其余响应将在执行特定命令后返回。

- ErrorResp
- KafkaFetchResp
- KafkaListOffsetResp

### 使用方法

#### 创建路由

创建一个路由，将上游的 `scheme` 字段设置为 `kafka`，并将 `nodes` 配置为 Kafka broker 的地址。

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/kafka' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/kafka",
    "upstream": {
        "nodes": {
            "kafka-server1:9092": 1,
            "kafka-server2:9092": 1,
            "kafka-server3:9092": 1
        },
        "type": "none",
        "scheme": "kafka"
    }
}'
```

配置路由后，就可以使用这一功能了。

#### 开启 TLS 和鉴权

仅需在创建的路由上开启 `kafka-proxy` 插件，通过配置即可开启与 Kafka TLS 握手和 SASL 鉴权，该插件配置可以参考 [插件文档](../../../en/latest/plugins/kafka-proxy.md)。

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/kafka' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/kafka",
    "plugins": {
        "kafka-proxy": {
            "enable_tls": true,
            "ssl_verify": true,
            "enable_sasl": true,
            "sasl_username": "user",
            "sasl_password": "pwd"
        }
    },
    "upstream": {
        "nodes": {
            "kafka-server1:9092": 1,
            "kafka-server2:9092": 1,
            "kafka-server3:9092": 1
        },
        "type": "none",
        "scheme": "kafka"
    }
}'
```
