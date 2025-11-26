---
title: Zookeeper
keywords:
  - API 网关
  - Apache APISIX
  - ZooKeeper
  - 服务发现
description: 本文档介绍了如何在 API 网关 Apache APISIX 上通过 ZooKeeper 实现服务发现。
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

## 通过 ZooKeeper 实现服务发现

Apache APISIX 支持与 ZooKeeper 集成以实现服务发现。这使得 APISIX 能够从 ZooKeeper 动态获取服务实例信息，并据此进行请求路由。

## ZooKeeper 配置

要启用 ZooKeeper 服务发现，请在 `conf/config.yaml` 中添加以下配置：

```yaml
discovery:
  zookeeper:
    connect_string: "127.0.0.1:2181,127.0.0.1:2182"  # ZooKeeper 集群地址（多个地址用逗号分隔）
    fetch_interval: 10     # 获取服务数据的间隔时间（秒）。默认值：10s
    weight: 100            # 服务实例的默认权重。默认值为 100，取值范围是 1-500。
    cache_ttl: 30          # 服务实例缓存过期时间。默认值：60s
    connect_timeout: 2000  # 连接超时时间（毫秒）。默认值：5000ms
    session_timeout: 30000 # 会话超时时间（毫秒）。默认值：30000ms
    root_path: "/apisix/discovery/zk"  # ZooKeeper 中服务注册的根路径，默认值："/apisix/discovery/zk"
    auth:                  # ZooKeeper 认证信息。格式要求："digest:{username}:{password}"。
      type: "digest"
      creds: "username:password"
```

您也可以使用默认值进行简化配置：

```yaml
discovery:
  zookeeper:
    connect_string: "127.0.0.1:2181"
```

### 上游设置

#### L7（HTTP/HTTPS）

以下示例将 URI 为 `/zookeeper/*` 的请求路由到在 ZooKeeper 中注册的名为 `APISIX-ZOOKEEPER` 的服务：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
$ admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/zookeeper/*",
    "upstream": {
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper"
    }
}'
```

格式化后的响应如下：

```json
{
  "node": {
    "key": "/apisix/routes/1",
    "value": {
      "id": "1",
      "create_time": 1690000000,
      "status": 1,
      "update_time": 1690000000,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper"
      },
      "priority": 0,
      "uri": "/zookeeper/*"
    }
  }
}
```

#### 四层（TCP/UDP）

ZooKeeper 服务发现也支持 L4 代理。以下是 TCP 的配置示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "scheme": "tcp",
        "discovery_type": "zookeeper",
        "service_name": "APISIX-ZOOKEEPER-TCP",
        "type": "roundrobin"
    }
}'
```

### 参数

| 名字         | 类型   | 可选项 | 默认值 | 有效值 | 说明                                                  |
| ------------ | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| root_path | string | 可选    | "/apisix/discovery/zk"     |       | ZooKeeper 中服务的自定义根路径 |

#### 指定根路径

路由到自定义根路径下服务的示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/zookeeper/custom/*",
    "upstream": {
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper",
        "discovery_args": {
            "root_path": "/custom/services"
        }
    }
}'
```

格式化后的响应如下：

```json
{
  "node": {
    "key": "/apisix/routes/2",
    "value": {
      "id": "2",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper",
        "discovery_args": {
          "root_path": "/custom/services"
        }
      },
      "priority": 0,
      "uri": "/zookeeper/*"
    }
  }
}
```
