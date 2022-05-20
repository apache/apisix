---
title: zookeeper
keywords:
  - APISIX
  - Zookeeper
  - apisix-seed
description: 本篇文档介绍了如何使用 Zookeeper 做服务发现
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

## 基于 [Zookeeper](https://zookeeper.apache.org/) 的服务发现

`Zookeeper` 服务发现需要依赖 [apisix-seed](https://github.com/api7/apisix-seed) 项目

### `apisix-seed` 工作原理

![APISIX-SEED](../../../assets/images/apisix-seed.svg)

`apisix-seed` 通过同时监听 `etcd` 和 `zookeeper` 的变化来完成数据交换。

流程如下：

1. `APISIX` 注册一个上游服务，并将服务类型设置为 `zookeeper` 并保存到 `etcd`。
2. `apisix-seed` 监听  `etcd` 中 `APISIX` 的资源变更并过滤服务发现类型获得服务名称。
3. `apisix-seed` 将服务绑定到 `etcd` 资源，并开始在 `zookeeper` 监听此服务。
4. 客户端向 `zookeeper` 注册该服务。
5. `apisix-seed` 获得 `zookeeper` 中的服务变更。
6. `apisix-seed` 通过服务名称查询绑定的 `etcd` 资源，并将更新的服务节点写回 `etcd`。
7. `APISIX` 工作节点监听 `etcd` 资源变更并在内存中刷新服务节点信息。

### 配置 `apisix-seed` 和 `Zookeeper`

配置步骤如下：

1. 启动 `Zookeeper` 服务

```bash
docker run -itd --rm --name=dev-zookeeper -p 2181:2181 zookeeper:3.7.0
```

2. 下载并编译 `apisix-seed` 项目

```bash
git clone https://github.com/api7/apisix-seed.git
cd apisix-seed
go build
```

3. 修改 `apisix-seed` 配置文件，路径设为 `conf/conf.yaml`

```bash
etcd:                            # APISIX ETCD Configure
  host:
    - "http://127.0.0.1:2379"
  prefix: /apisix
  timeout: 30

discovery:
  zookeeper:                     # Zookeeper Service Discovery
    hosts:
      - "127.0.0.1:2181"         # Zookeeper service address
    prefix: /zookeeper
    weight: 100                  # default weight for node
    timeout: 10                  # default 10s
```

4. 启动 `apisix-seed` 以监听服务变更

```bash
./apisix-seed
```

### 设置 `APISIX` 路由和上游

设置一个路由，请求路径为 `/zk/*`，上游使用 `zookeeper` 作为服务发现，服务名称是 `APISIX-ZK`

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/zk/*",
    "upstream": {
        "service_name": "APISIX-ZK",
        "type": "roundrobin",
        "discovery_type": "zookeeper"
    }
}'
```

### 注册服务和请求验证

1. 使用 `Zookeeper CLI` 注册服务

- 注册服务

```bash
# 登陆容器
docker exec -it ${CONTAINERID} /bin/bash
# 登陆 Zookeeper 客户端
oot@ae2f093337c1:/apache-zookeeper-3.7.0-bin# ./bin/zkCli.sh
# 注册服务
[zk: localhost:2181(CONNECTED) 0] create /zookeeper/APISIX-ZK '{"host":"127.0.0.1:1980","weight":100}'
```

- 响应成功

```bash
Created /zookeeper/APISIX-ZK
```

2. 请求验证

- 请求

```bash
curl -i http://127.0.0.1:9080/zk/hello
```

- 响应

```bash
HTTP/1.1 200 OK
Connection: keep-alive
Content-Type: text/html; charset=utf-8
Date: Tue, 29 Mar 2022 08:51:28 GMT
Server: APISIX/2.12.0
Transfer-Encoding: chunked
...
hello
```
