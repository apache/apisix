---
title: mqtt-proxy
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

`mqtt-proxy` 只工作在流模式，它可以帮助你根据 MQTT 的 `client_id` 实现动态负载均衡。

这个插件支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 及 [5.0]( https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html ) 两个协议。

## 属性

| 名称           | 类型    | 必选项 | 默认值 | 有效值 | 描述                                                   |
| -------------- | ------- | ------ | ------ | ------ | ------------------------------------------------------ |
| protocol_name  | string  | 必须   |        |        | 协议名称，正常情况下应为“ MQTT”                        |
| protocol_level | integer | 必须   |        |        | 协议级别，MQTT `3.1.*` 应为 `4` ，MQTT `5.0` 应是`5`。 |
| upstream       | object  | 废弃   |         |       | 推荐改用 route 上配置的上游信息                                            |
| upstream.host  | string  | 必须   |        |        | 将当前请求转发到的上游的 IP 地址或域名                  |
| upstream.ip    | string  | 废弃   |        |        | 推荐使用“host”代替。将当前请求转发到的上游的 IP 地址                       |
| upstream.port  | number  | 必须   |        |        | 将当前请求转发到的上游的端口                           |

## 如何启用

为了启用该插件，需要先在 `conf/config.yaml` 中首先开启 stream_proxy 配置，比如下面配置代表监听 9100 TCP 端口：

```yaml
    ...
    router:
        http: 'radixtree_uri'
        ssl: 'radixtree_sni'
    stream_proxy:                 # TCP/UDP proxy
      only: false                 # 如需 HTTP 与 Stream 代理同时生效，需要增加该键值
      tcp:                        # TCP proxy port list
        - 9100
    dns_resolver:
    ...
```

然后把 MQTT 请求发送到 9100 端口即可。

下面是一个示例，在指定的 route 上开启了 `mqtt-proxy` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

在 Docker 与 MacOS 结合使用的情况下，`host.docker.internal` 是 `host` 的正确参数。

这个插件暴露了一个变量 `mqtt_client_id`，我们可以用它来通过客户端 ID 进行负载均衡。比如说:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

不同客户端 ID 的 MQTT 连接将通过一致性哈希算法被转发到不同的节点。如果客户端 ID 为空，我们将通过客户端 IP 进行均衡。

#### 禁用插件

当你想去掉插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
```

现在就已经移除了 mqtt-proxy 插件了。
