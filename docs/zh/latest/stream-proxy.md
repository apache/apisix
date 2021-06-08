---
title: TCP/UDP 动态代理
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

众多的闻名的应用和服务，像 LDAP、 MYSQL 和 RTMP ，选择 TCP 作为通信协议。 但是像 DNS、 syslog 和 RADIUS 这类非事务性的应用，他们选择了 UDP 协议。

APISIX 可以对 TCP/UDP 协议进行代理并实现动态负载均衡。 在 nginx 世界，称 TCP/UDP 代理为 stream 代理，在 APISIX 这里我们也遵循了这个声明.

## 如何开启 Stream 代理?

在 `conf/config.yaml` 配置文件设置 `stream_proxy` 选项， 指定一组需要进行动态代理的 IP 地址。默认情况不开启 stream 代理。

```yaml
apisix:
  stream_proxy: # TCP/UDP proxy
    tcp: # TCP proxy address list
      - 9100
      - "127.0.0.1:9101"
    udp: # UDP proxy address list
      - 9200
      - "127.0.0.1:9211"
```

## 如何设置 route ?

简例如下:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

例子中 APISIX 对客户端 IP 为 `127.0.0.1` 的请求代理转发到上游主机 `127.0.0.1:1995`。
更多用例，请参照 [test case](../../../t/stream-node/sanity.t).

## 更多 route 匹配选项

我们可以添加更多的选项来匹配 route 。

例如

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "server_addr": "127.0.0.1",
    "server_port": 2000,
    "upstream": {
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

例子中 APISIX 会把服务器地址为 `127.0.0.1`, 端口为 `2000` 代理到上游地址 `127.0.0.1:1995`。

完整的匹配选项列表参见 [Admin API 的 Stream Route](./admin-api.md#stream-route)。
