---
title: Apache Kafka
keywords:
  - Apache APISIX
  - API Gateway
  - PubSub
  - Kafka
description: This document contains information about the Apache APISIX kafka pubsub scenario.
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

## Connect to Apache Kafka

Connecting to Apache Kafka in Apache APISIX is very simple.

Currently, we provide a simpler way to integrate by combining two APIs, ListOffsets and Fetch, to quickly implement the ability to pull Kafka messages. Still, they do not support Apache Kafka's consumer group feature for now and cannot be managed for offsets by Apache Kafka.

### Limitations

- Offsets need to be managed manually

They can be stored by a custom backend service or obtained via the list_offset command before starting to fetch the message, which can use timestamp to get the starting offset, or to get the initial and end offsets.

- Unsupported batch data acquisition

A single instruction can only obtain the data of a Topic Partition, does not support batch data acquisition through a single instruction

### Prepare

First, it is necessary to compile the [communication protocol](https://github.com/apache/apisix/blob/master/apisix/include/apisix/model/pubsub.proto) as a language-specific SDK using the `protoc`, which provides the command and response definitions to connect to Kafka via APISIX using the WebSocket.

The `sequence` field in the protocol is used to associate the request with the response, they will correspond one to one, the client can manage it in the way they want, APISIX will not modify it, only pass it back to the client through the response body.

The following commands are currently used by Apache Kafka connect：

- CmdKafkaFetch
- CmdKafkaListOffset

> The `timestamp` field in the `CmdKafkaListOffset` command supports the following value:
>
> - `unix timestamp`: Offset of the first message after the specified timestamp
> - `-1`：Offset of the last message of the current Partition
> - `-2`：Offset of the first message of current Partition
>
> For more information, see [Apache Kafka Protocol Documentation](https://kafka.apache.org/protocol.html#The_Messages_ListOffsets)

Possible response body: When an error occurs, `ErrorResp` will be returned, which includes the error string; the rest of the response will be returned after the execution of the particular command.

- ErrorResp
- KafkaFetchResp
- KafkaListOffsetResp

### How to use

#### Create route

Create a route, set the upstream `scheme` field to `kafka`, and configure `nodes` to be the address of the Kafka broker.

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/kafka' \
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

After configuring the route, you can use this feature.

#### Enabling TLS and SASL/PLAIN authentication

Simply turn on the `kafka-proxy` plugin on the created route and enable the Kafka TLS handshake and SASL authentication through the configuration, which can be found in the [plugin documentation](../../../en/latest/plugins/kafka-proxy.md).

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/kafka' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/kafka",
    "plugins": {
        "kafka-proxy": {
            "sasl": {
                "username": "user",
                "password": "pwd"
            }
        }
    },
    "upstream": {
        "nodes": {
            "kafka-server1:9092": 1,
            "kafka-server2:9092": 1,
            "kafka-server3:9092": 1
        },
        "type": "none",
        "scheme": "kafka",
        "tls": {
            "verify": true
        }
    }
}'
```
