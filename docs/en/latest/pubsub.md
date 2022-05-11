---
title: PubSub
keywords:
  - APISIX
  - Pub-Sub
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

## What is Pub-Sub

Publish-subscribe is a messaging paradigm in which message producers do not send messages directly to message consumers, but are relayed by a specific broker that caches messages sent by producers and then actively pushes them to subscribed consumers or pulls them by consumers. This pattern is often used in system architectures for system decoupling or to handle high traffic scenarios.

In Apache APISIX, the most common scenario is for handling north-south traffic from the server to the client. If we can combine it with a publish-subscribe scenario, we can achieve more powerful features, such as real-time collaboration on online documents, online games, etc.

## Architecture

![pub-sub architecture](../../assets/images/pubsub-architecture.svg)

Currently, Apache APISIX supports WebSocket communication with the client, which can be any application that supports WebSocket, with Protocol Buffer as the serialization mechanism, see the [protocol definition](../../../apisix/pubsub.proto).

## Supported messaging systems

- [Aapche Kafka](pubsub/kafka.md)

## How to support other messaging systems

An extensible pubsub module is implemented in Apache APISIX, which is responsible for starting the WebSocket server, coding and decoding communication protocols, handling client commands, and through which new messaging system support can be simply added.

### Basic Steps

- Add new commands and response body definitions to `pubsub.proto`
- Add a new option to the `scheme` configuration item in upstream
- Add a new `scheme` judgment branch to `http_access_phase`
- Implement the required message system instruction processing functions
- Optional: Create plugins to support advanced configurations of this messaging system

### the example of Apache Kafka

#### Add new commands and response body definitions to `pubsub.proto`

The core of the protocol definition in `pubsub.proto` is the two parts `PubSubReq` and `PubSubResp`.

First, create the `CmdKafkaFetch` command and add the required parameters. Then, register this command in the list of commands for `req` in `PubSubReq`, which is named `cmd_kafka_fetch`.

```protobuf
message CmdKafkaFetch {
    string topic = 1;
    int32 partition = 2;
    int64 offset = 3;
}

message PubSubReq {
    int64 sequence = 1;
    oneof req {
        CmdKafkaFetch cmd_kafka_fetch = 31;
        // more commands
    };
}
```

Then create the corresponding response body `KafkaFetchResp` and register it in the `resp` of `PubSubResp`, named `kafka_fetch_resp`.

```protobuf
message KafkaFetchResp {
    repeated KafkaMessage messages = 1;
}

message PubSubResp {
    int64 sequence = 1;
    oneof resp {
        ErrorResp error_resp = 31;
        KafkaFetchResp kafka_fetch_resp = 32;
        // more responses
    };
}
```

#### Add a new option to the `scheme` configuration item in upstream

Add a new option `kafka` to the `scheme` field enumeration in the `upstream` of `apisix/schema_def.lua`.

```lua
scheme = {
    enum = {"grpc", "grpcs", "http", "https", "tcp", "tls", "udp", "kafka"},
    -- other
}
```

#### Add a new `scheme` judgment branch to `http_access_phase`

Add a `scheme` judgment branch to the `http_access_phase` function in `apisix/init.lua` to support the processing of `kafka` type upstreams. Because of Apache Kafka has its own clustering and partition scheme, we do not need to use the Apache APISIX built-in load balancing algorithm, so we intercept and take over the processing flow before selecting the upstream node, here using the `kafka_access_phase` function.

```lua
-- load balancer is not required by kafka upstream
if api_ctx.matched_upstream and api_ctx.matched_upstream.scheme == "kafka" then
    return kafka_access_phase(api_ctx)
end
```

#### Implement the required message system commands processing functions

```lua
local function kafka_access_phase(api_ctx)
    local pubsub, err = core.pubsub.new()

    -- omit kafka client initialization code here

    pubsub:on("cmd_kafka_list_offset", function (params)
        -- call kafka client to get data
    end)

    pubsub:wait()
end
```

First, create an instance of the `pubsub` module, which is provided in the `core` package.

```lua
local pubsub, err = core.pubsub.new()
```

Then, an instance of the Apache Kafka client is created, and this code is omitted here.

Next, add the command registered in the protocol definition above to the `pubsub` instance, which will provide a callback function that provides the parameters parsed from the communication protocol, in which the developer needs to call the kafka client to get the data and return it to the `pubsub` module as the function return value.

```lua
pubsub:on("cmd_kafka_list_offset", function (params)

end)
```

:::note Callback function prototype
The `params` is the data in the protocol definition; the first return value is the data, which needs to contain the fields in the response body definition, and returns the `nil` value when there is an error; the second return value is the error, and returns the error string when there is an error

```lua
function (params)
    return data, err
end
```

:::

Finally, it enters the loop to wait for client commands and when an error occurs it returns the error and stops the processing flow.

```lua
local err = pubsub:wait()
```

#### Optional: Create plugins to support advanced configurations of this messaging system

Add the required fields to the plugin schema definition and write them to the context of the current request in the `access` function.

```lua
local schema = {
    type = "object",
    properties = {
        enable_tls = {
            type = "boolean",
            default = false,
        },
        -- more properties
    },
}

local _M = {
    version = 0.1,
    priority = 508,
    name = "kafka-proxy",
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    ctx.kafka_consumer_enable_tls = conf.enable_tls
    ctx.kafka_consumer_ssl_verify = conf.ssl_verify
    ctx.kafka_consumer_enable_sasl = conf.enable_sasl
    ctx.kafka_consumer_sasl_username = conf.sasl_username
    ctx.kafka_consumer_sasl_password = conf.sasl_password
end
```

Add this plugin to the list of plugins in the APISIX configuration file.

```yaml
# config-default.yaml
plugins:
  - kafka-proxy
```

#### Results

After this is done, create a route like the one below to connect to this messaging system via APISIX using the WebSocket.

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
        "scheme": "kafka",
        "tls": {
            "verify": true
        }
    }
}'
```
