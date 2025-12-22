---
title: mqtt-proxy
keywords:
  - APISIX
  - API 网关
  - Plugin
  - MQTT Proxy
description: 本文档介绍了 Apache APISIX mqtt-proxy 插件的信息，通过 `mqtt-proxy` 插件可以使用 MQTT 的 `client_id` 进行动态负载平衡。
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

通过 `mqtt-proxy` 插件可以使用 MQTT 的 `client_id` 进行动态负载平衡。它仅适用于 `stream` 模式。

这个插件支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 及 [5.0]( https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html ) 两个协议。

## 属性

| 名称           | 类型     | 必选项 | 描述                                                 |
| -------------- | ------- | ----- | --------------------------------------------------- |
| protocol_name  | string  | 否    | 协议名称，默认为 `MQTT`。                               |
| protocol_level | integer | 是    | 协议级别，MQTT `3.1.*` 为 `4`，MQTT `5.0` 应是`5`。     |

## 启用插件

为了启用该插件，需要先在配置文件（`./conf/config.yaml`）中加载 `stream_proxy` 相关配置。以下配置代表监听 `9100` TCP 端口：

```yaml title="./conf/config.yaml"
    ...
    router:
        http: 'radixtree_uri'
        ssl: 'radixtree_sni'
    proxy_mode: http&stream
    stream_proxy:                 # TCP/UDP proxy
      tcp:                        # TCP proxy port list
        - 9100
    dns_resolver:
    ...
```

现在你可以将请求发送到 `9100` 端口。

你可以创建一个 stream 路由并启用 `mqtt-proxy` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": [{
            "host": "127.0.0.1",
            "port": 1980,
            "weight": 1
        }]
    }
}'
```

如果你在 macOS 中使用 Docker，则 `host.docker.internal` 是 `host` 的正确属性。

该插件暴露了一个变量 `mqtt_client_id`，你可以使用它来通过客户端 ID 进行负载均衡。比如：

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "upstream": {
        "type": "chash",
        "key": "mqtt_client_id",
        "nodes": [
        {
            "host": "127.0.0.1",
            "port": 1995,
            "weight": 1
        },
        {
            "host": "127.0.0.2",
            "port": 1995,
            "weight": 1
        }
        ]
    }
}'
```

不同客户端 ID 的 MQTT 连接将通过一致性哈希算法被转发到不同的节点。如果客户端 ID 为空，将会通过客户端 IP 进行均衡。

## 使用 mqtt-proxy 插件启用 mTLS

Stream 代理可以使用 TCP 连接并且支持 TLS。请参考 [如何通过 tcp 连接接受 tls](../stream-proxy.md/#accept-tls-over-tcp-connection) 打开启用了 TLS 的 stream 代理。

`mqtt-proxy` 插件通过 Stream 代理的指定端口的 TCP 通信启用，如果 `tls` 设置为 `true`，则还要求客户端通过 TLS 进行身份验证。

配置 `ssl` 提供 CA 证书和服务器证书，以及 SNI 列表。使用 `ssl` 保护 `stream_routes` 的步骤等同于 [protect Routes](../mtls.md/#protect-route)。

### 创建 stream_route 并配置 mqtt-proxy 插件和 mTLS

通过以下示例可以创建一个配置了 `mqtt-proxy` 插件的 `stream_route`，需要提供 CA 证书、客户端证书和客户端密钥（对于不受主机信任的自签名证书，请使用 -k 选项）：

```shell
curl 127.0.0.1:9180/apisix/admin/stream_routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "sni": "${your_sni_name}",
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    }
}'
```

:::note 注意

`sni` 名称必须与提供的 CA 和服务器证书创建的 SSL 对象的一个​​或多个 SNI 匹配。

:::

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
-H "X-API-KEY: $admin_key" -X DELETE
```
