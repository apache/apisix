---
title: 发布订阅框架
keywords:
  - APISIX
  - Pub-Sub
description: This document contains information about the Apache APISIX pub-sub framework.
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

## 摘要

发布订阅是一种消息范式，消息生产者不直接将消息发送给消息消费者，而是由特定的代理进行中转，代理会将生产者发送的消息缓存下来，之后主动推送至订阅的消费者或由消费者拉取。在系统架构中通常使用这种模式进行系统解耦，或是处理大流量场景。

在 Apache APISIX 中，最常用的场景是用于处理服务器至客户端的南北向流量，如果可以结合发布订阅场景，我们可以实现更为强大的功能，例如在线文档实时协作、在线游戏等。

## 架构

![pub-sub architecture](../../assets/images/pubsub-architecture.svg)

当前，Apache APISIX 支持以 WebSocket 与客户端通信，客户端可以是任何支持 WebSocket 的程序，以自定义 Protocol Buffer 为应用层通信协议，查看[协议定义](../../../apisix/pubsub.proto)。

## 当前支持的消息系统

- [Aapche Kafka](pubsub/kafka.md)

## 如何支持其他消息系统

Apache APISIX 中为此实现了一个可扩展的 pubsub 模块，它负责启动 WebSocket 服务器、通信协议编解码、处理客户端指令，通过它可以简单的添加新的消息系统支持。

### 基本步骤

- 向`pubsub.proto`中添加新的指令和响应体定义
- 向上游中`scheme`配置项添加新的选项
- 向`http_access_phase`中添加新的`scheme`判断分支
- 实现所需消息系统指令处理函数
- 可选：创建插件以支持该消息系统的高级配置

### 以 Apache Kafka 为例

#### 向`pubsub.proto`中添加新的指令和响应体定义

`pubsub.proto`中协议定义的核心为`PubSubReq`和`PubSubResp`这两个部分。

首先，创建`CmdKafkaFetch`指令，添加所需的参数。而后，在`PubSubReq`中 req 的指令列表中注册这条指令，其命名为`cmd_kafka_fetch`。

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

接着创建对应的响应体`KafkaFetchResp`并在`PubSubResp`的 resp 中注册它，其命名为`kafka_fetch_resp`。

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

#### 向上游中`scheme`配置项添加新的选项

在`apisix/schema_def.lua`的`upstream`中`scheme`字段枚举中添加新的选项`kafka`。

```lua
scheme = {
    enum = {"grpc", "grpcs", "http", "https", "tcp", "tls", "udp", "kafka"},
    -- other
}
```

#### 向`http_access_phase`中添加新的`scheme`判断分支

在`apisix/init.lua`的`http_access_phase`函数中添加`scheme`的判断分支，以支持`kafka`类型的上游的处理。因为 Apache Kafka 有其自己的集群与分片方案，我们不需要使用 Apache APISIX 内置的负载均衡算法，因此在选择上游节点前拦截并接管处理流程，此处使用`kafka_access_phase`函数。

```lua
-- load balancer is not required by kafka upstream
if api_ctx.matched_upstream and api_ctx.matched_upstream.scheme == "kafka" then
    return kafka_access_phase(api_ctx)
end
```

#### 实现所需消息系统指令处理函数

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

首先，创建`pubsub`模块实例，它在`core`包中提供。

```lua
local pubsub, err = core.pubsub.new()
```

创建需要的 Apache Kafka 客户端实例，此处省略这部分代码。

接着，在`pubsub`实例中添加在上面协议定义中注册的指令，其中将提供一个回调函数，它的提供从通信协议中解析出的参数，开发者需要在这个回调函数中调用 kafka 客户端获取数据，并作为函数返回值返回至`pubsub`模块。

```lua
pubsub:on("cmd_kafka_list_offset", function (params)
end)
```

:::note 回调函数原型
params为协议定义中的数据；第一个返回值为数据，它需要包含响应体定义中的字段，当出现错误时则返回`nil`值；第二个返回值为错误，当出现错误时返回错误字符串
```lua
function (params)
    return data, err
end
```
:::

最终，进入循环等待客户端指令，当出现错误时它将返回错误并停止处理流程。

```lua
local err = pubsub:wait()
```

#### 可选：创建`kafka-proxy`插件以支持其鉴权配置

在插件 schema 定义中添加所需的字段，而后在 `access` 处理函数中将它们写入当前请求的上下文中。

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

最后，需要将此插件注册至 APISIX 配置文件中的插件列表。

```yaml
# config-default.yaml
plugins:
  - kafka-proxy
```

#### 成果

在完成上述工作后，创建下面这样的路由，即可通过 APISIX 以 WebSocket 连接这种消息系统。

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
