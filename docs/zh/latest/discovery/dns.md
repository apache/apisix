---
title: DNS
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

## 基于 DNS 的服务发现

某些服务发现系统如 Consul，支持通过 DNS 提供系统信息。我们可以使用这种方法直接实现服务发现，七层与四层均支持。

首先我们需要配置 DNS 服务器的地址：

```yaml
# 添加到 config.yaml
discovery:
   dns:
     servers:
       - "127.0.0.1:8600"          # 使用 DNS 服务器的真实地址
```

与在 Upstream 的 `nodes` 对象中配置域名不同的是，DNS 服务发现将返回所有的记录。例如按照以下的 upstream 配置：

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "test.consul.service",
    "type": "roundrobin"
}
```

之后 `test.consul.service` 将被解析为 `1.1.1.1` 和 `1.1.1.2`，这个结果等同于：

```json
{
    "id": 1,
    "type": "roundrobin",
    "nodes": [
        {"host": "1.1.1.1", "weight": 1},
        {"host": "1.1.1.2", "weight": 1}
    ]
}
```

注意所有来自 `test.consul.service` 的 IP 都有相同的权重。

解析的记录将根据它们的 TTL 来进行缓存。对于记录不在缓存中的服务，我们将默认按照 `SRV -> A -> AAAA -> CNAME` 的顺序进行查询，刷新缓存记录时，我们将从上次成功的类型开始尝试。也可以通过修改配置文件来自定义 DNS 的解析顺序。

```yaml
# 添加到 config.yaml
discovery:
   dns:
     servers:
       - "127.0.0.1:8600"          # 使用 DNS 服务器的真实地址
     order:                        # DNS 解析的顺序
       - last                      # "last" 表示从上次成功的类型开始
       - SRV
       - A
       - AAAA
       - CNAME

```

如果你想指定 upstream 服务器的端口，可以把以下内容添加到 `service_name`：

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "test.consul.service:1980",
    "type": "roundrobin"
}
```

另一种方法是通过 SRV 记录，见如下。

### SRV 记录

通过使用 SRV 记录你可以指定一个服务的端口和权重。

假设你有一条这样的 SRV 记录：

```
; under the section of blah.service
A       300 IN      A     1.1.1.1
B       300 IN      A     1.1.1.2
B       300 IN      A     1.1.1.3

; name  TTL         type    priority    weight  port
srv     86400 IN    SRV     10          60      1980 A
srv     86400 IN    SRV     20          20      1981 B
```

Upstream 配置是这样的：

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "srv.blah.service",
    "type": "roundrobin"
}
```

效果等同于：

```json
{
    "id": 1,
    "type": "roundrobin",
    "nodes": [
        {"host": "1.1.1.1", "port": 1980, "weight": 60, "priority": -10},
        {"host": "1.1.1.2", "port": 1981, "weight": 10, "priority": -20},
        {"host": "1.1.1.3", "port": 1981, "weight": 10, "priority": -20}
    ]
}
```

注意 B 域名的两条记录均分权重。
对于 SRV 记录，低优先级的节点被先选中，所以最后一项的优先级是负数。

关于 0 权重的 SRV 记录，在 [RFC 2782](https://www.ietf.org/rfc/rfc2782.txt) 中是这么描述的：

> 当没有任何候选服务器时，域管理员应使用权重为 0 的，使 RR 更为易读（噪音更少）。当存在权重大于 0 的记录时，权重为 0 的记录被选中的可能性很小。

我们把权重为 0 的记录当作权重为 1，因此节点“被选中的可能性很小”，这也是处理此类记录的常用方法。

对于端口为 0 的 SRV 记录，我们会使用上游协议的默认端口。
你也可以在“service_name”字段中直接指定端口，比如“srv.blah.service:8848”。
