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

- [English](../../plugins/mqtt-proxy.md)

# 目录

- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**禁用插件**](#禁用插件)

## 名字

`mqtt-proxy` 只工作在流模式，它可以帮助你根据 MQTT 的 `client_id` 实现动态负载均衡。

这个插件支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 及[5.0]( https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html )两个协议。

## 属性

* `protocol_name`: 必选，协议名称，正常情况下应为“ MQTT” 。
* `protocol_level`: 必选，协议级别，MQTT `3.1.*` 应为 “4” ，MQTT `5.0` 应该是“5”。
* `upstream.ip`: 必选，将当前请求转发到的上游的 IP 地址，
* `upstream.port`: 必选，将当前请求转发到的上游的 端口，

| 名称           | 类型    | 必选项 | 默认值 | 有效值 | 描述                                                   |
| -------------- | ------- | ------ | ------ | ------ | ------------------------------------------------------ |
| protocol_name  | string  | 必须   |        |        | 协议名称，正常情况下应为“ MQTT”                        |
| protocol_level | integer | 必须   |        |        | 协议级别，MQTT `3.1.*` 应为 `4` ，MQTT `5.0` 应是`5`。 |
| upstream.ip    | string  | 必须   |        |        | 将当前请求转发到的上游的 IP 地址                       |
| upstream.port  | number  | 必须   |        |        | 将当前请求转发到的上游的端口                           |

## 如何启用

为了启用该插件，需要先在 `conf/config.yaml` 中首先开启 stream_proxy 配置，比如下面配置代表监听 9100 TCP 端口：

```yaml
    ...
    router:
        http: 'radixtree_uri'
        ssl: 'radixtree_sni'
    stream_proxy:                 # TCP/UDP proxy
      tcp:                        # TCP proxy port list
        - 9100
    dns_resolver:
    ...
```

然后把 MQTT 请求发送到 9100 端口即可。

下面是一个示例，在指定的 route 上开启了 mqtt-proxy 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "remote_addr": "127.0.0.1",
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4,
            "upstream": {
                "ip": "127.0.0.1",
                "port": 1980
            }
        }
    }
}'
```

#### 禁用插件

当你想去掉插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/stream_routes/1 -X DELETE
```

现在就已经移除了 mqtt-proxy 插件了。
