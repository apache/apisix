---
title: websocket-proxy
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - WebSocket proxy
description: 本文介绍了关于 Apache APISIX `websocket-proxy` 插件的基本信息及使用方法。
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

`websocket-proxy` 插件用于给 `upstream.scheme` 为 `ws` 或 `wss` 的路由配置高级参数。目前它控制的是 APISIX 在连接两侧各自能接受的单个 WebSocket 帧的最大尺寸。

默认情况下，APISIX 接受来自下游客户端或上游的单帧最大为 65535 字节，超过这个尺寸的单帧会导致连接被关闭。`enable_websocket` 没有这个限制，因为它让 nginx 直接转发原始字节、不解析帧；但 `scheme: ws`/`wss` 会解析每一帧以便运行插件逻辑，底层库如果不特别设置就会对单帧尺寸设上限。这个插件就是给需要收发更大消息的路由（比如客户端用一个 WebSocket 消息上传一个文件）放开这个上限用的。

## 属性

下表里每一项都是"端点级"的限制，不只是"从对端接收"的限制：它还会同时抬高*另一个*端点的发送上限，因为转发出去的消息，本质上都是从对端刚收进来又原样发出去的。所以只配置 `client_max_payload_len` 就足够让一条大的客户端消息一路转发到上游：它同时抬高了面向客户端一侧能接受多大的消息、以及面向上游一侧被允许发送多大的消息。这两个属性彼此独立，所以不对称的配置（只抬高一个、另一个保持默认，或者两个配成不同的值）是合法的，各自方向都会按预期工作。

| 名称                      | 类型    | 必选项 | 默认值 | 有效值          | 描述 |
|---------------------------|---------|-----|--------|-----------------|------|
| client_max_payload_len    | integer | 否   |        | 1 - 2147483647  | 这个路由能接受的、来自下游客户端的单个 WebSocket 消息的最大字节数，同时也是它能从客户端转发到上游的单个消息的最大字节数。不设置时按默认值 65535 处理。 |
| upstream_max_payload_len  | integer | 否   |        | 1 - 2147483647  | 这个路由能接受的、来自上游的单个 WebSocket 消息的最大字节数，同时也是它能从上游转发到客户端的单个消息的最大字节数。不设置时按默认值 65535 处理。 |

## 示例

创建一个 `upstream.scheme` 为 `ws` 的路由，并用这个插件把两侧的帧尺寸上限都放开：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/ws",
    "plugins": {
        "websocket-proxy": {
            "client_max_payload_len": 1048576,
            "upstream_max_payload_len": 1048576
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin",
        "scheme": "ws"
    }
}'
```

现在，`/ws` 这条路由上不管哪个方向、单条消息只要不超过 1 MiB 就不会再导致连接被关闭。

## FAQ

### 这个插件对使用 `enable_websocket` 的路由生效吗？

不生效。它只对 `upstream.scheme` 为 `ws` 或 `wss` 的路由起作用。`enable_websocket` 用的是 nginx 自己的 `proxy_pass` 直接转发原始字节，压根不解析帧，所以在那条路径上也就没有这个插件要放开的帧尺寸限制可言。两者的区别可以参考 [Admin API 参考文档里 scheme 的说明](../admin-api.md#upstream)。

### 我抬高了 `client_max_payload_len`，但上游发来的大消息还是到不了客户端

这两个属性彼此独立。`client_max_payload_len` 覆盖的是客户端发起的消息在两个方向上的转发（参见[属性](#属性)）；上游发起的大消息需要抬高的是 `upstream_max_payload_len`。

### 我的配置被拒绝了，报错里提到 2147483647

`api7-lua-resty-websocket` 只用 31 位编码帧长度，所以这两个属性都不接受超过 2147483647（2^31 - 1）的值，超过这个值在配置阶段就会被拒绝，而不是留到运行时才不可预知地失败。如果需要更大的消息，把这个值调小，或者把要传的内容拆成多个 WebSocket 消息发送。

## 删除插件

要移除 `websocket-proxy` 插件，只需在插件配置中删除相应的 JSON 配置，APISIX 会自动重新加载，无需重启服务。
