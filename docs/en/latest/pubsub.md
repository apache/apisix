---
title: PubSub
keywords:
  - APISIX
  - PubSub
description: This document contains information about the Apache APISIX pubsub framework.
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

## What is PubSub

Publish-subscribe is a messaging paradigm:

- Producers send messages to specific brokers rather than directly to consumers.
- Brokers cache messages sent by producers and then actively push them to subscribed consumers or pull them.

The system architectures use this pattern to decouple or handle high traffic scenarios.

In Apache APISIX, the most common scenario is handling north-south traffic from the server to the client. Combining it with a publish-subscribe system, we can achieve more robust features, such as real-time collaboration on online documents, online games, etc.

## Architecture

![pubsub architecture](../../assets/images/pubsub-architecture.svg)

Currently, Apache APISIX supports WebSocket communication with the client, which can be any application that supports WebSocket, with Protocol Buffer as the serialization mechanism, see the [protocol definition](https://github.com/apache/apisix/blob/master/apisix/include/apisix/model/pubsub.proto).

## Supported messaging systems

- [Aapche Kafka](pubsub/kafka.md)

## How to support other messaging systems

Apache APISIX implement an extensible pubsub module, which is responsible for starting the WebSocket server, coding and decoding communication protocols, handling client commands, and adding support for the new messaging system.

### Basic Steps

- Add new commands and response body definitions to `pubsub.proto`
- Add a new option to the `scheme` configuration item in upstream
- Add a new `scheme` judgment branch to `http_access_phase`
- Implement the required message system instruction processing functions
- Optional: Create plugins to support advanced configurations of this messaging system

### Example

TODO, an example will be added later to point out how to support other messaging systems.
