---
title: consul
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

## 概述

APACHE APISIX 支持使用 [Consul](https://developer.hashicorp.com/consul) 作为服务发现。

## 服务发现客户端配置

### Consul 配置

首先，我们需要在 `conf/config.yaml` 中添加如下配置：

```yaml
discovery:
  consul:
    servers:                      # 确保这些 Consul 服务器中的服务名是唯一的
      - "http://127.0.0.1:8500"   # `http://127.0.0.1:8500` 和 `http://127.0.0.1:8600` 是不同的集群
      - "http://127.0.0.1:8600"   # 默认跳过的服务名是 `consul`
    token: "..."                  # 如果 Consul 启用了 ACL 访问控制，需要指定 token
    skip_services:                # 如果需要跳过某些服务
      - "service_a"
    timeout:
      connect: 1000               # 默认 2000 毫秒
      read: 1000                  # 默认 2000 毫秒
      wait: 60                    # 默认 60 秒
    weight: 1                     # 默认 1
    fetch_interval: 5             # 默认 3 秒，仅在 keepalive 为 false 时生效
    keepalive: true               # 默认 true，采用长轮询方式查询 Consul 服务器
    sort_type: "origin"           # 默认 origin
    default_service:              # 当未命中时可以定义默认服务
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1           # 默认 1 毫秒
        weight: 1                 # 默认 1
        max_fails: 1              # 默认 1
    dump:                         # 如果需要，在注册节点更新时可写入文件
       path: "logs/consul.dump"
       expire: 2592000            # 单位为秒，此处为 30 天
```

你也可以使用默认值进行简化配置：

```yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
```

`keepalive` 有两个可选值：

* `true`：默认且推荐，使用长轮询方式查询 Consul
* `false`：不推荐，使用短轮询方式查询，可设置 `fetch_interval` 来定义拉取间隔

`sort_type` 有四种可选值：

* `origin`：不排序
* `host_sort`：按主机排序
* `port_sort`：按端口排序
* `combine_sort`：在主机排序的前提下对端口也排序

#### 数据转储

当我们需要在线 reload `apisix` 时，Consul 模块可能比从 ETCD 加载路由更慢，可能会出现如下日志：

```
 http_access_phase(): failed to set upstream: no valid upstream node
```

因此我们引入了 `dump` 功能。当 reload 时，会优先加载 dump 文件；当 Consul 中注册的节点更新时，会自动将上游节点写入文件。

`dump` 支持三个配置项：

* `path`：转储文件保存路径

    * 支持相对路径，如：`logs/consul.dump`
    * 支持绝对路径，如：`/tmp/consul.dump`
    * 确保父目录存在
    * 确保 `apisix` 进程有读写权限，如可在 `conf/config.yaml` 中加入：

```yaml
nginx_config:                     # 渲染模板生成 nginx.conf 的配置
  user: root                      # 指定 worker 进程的运行用户
```

* `load_on_init`，默认值为 `true`

    * 如果为 `true`，在加载 Consul 数据之前尝试读取 dump 文件
    * 如果为 `false`，则忽略 dump 文件
    * 无论为 `true` 还是 `false`，都无需预先准备 dump 文件
* `expire`：单位为秒，用于避免加载过期 dump 数据

    * 默认值为 `0`，永不过期
    * 推荐设置为 2592000，即 30 天（3600 × 24 × 30）

### 注册 HTTP API 服务

将节点注册到 Consul：

```shell
curl -X PUT 'http://127.0.0.1:8500/v1/agent/service/register' \
-d '{
  "ID": "service_a1",
  "Name": "service_a",
  "Tags": ["primary", "v1"],
  "Address": "127.0.0.1",
  "Port": 8000,
  "Meta": {
    "service_a_version": "4.0"
  },
  "EnableTagOverride": false,
  "Weights": {
    "Passing": 10,
    "Warning": 1
  }
}'

curl -X PUT 'http://127.0.0.1:8500/v1/agent/service/register' \
-d '{
  "ID": "service_a1",
  "Name": "service_a",
  "Tags": ["primary", "v1"],
  "Address": "127.0.0.1",
  "Port": 8002,
  "Meta": {
    "service_a_version": "4.0"
  },
  "EnableTagOverride": false,
  "Weights": {
    "Passing": 10,
    "Warning": 1
  }
}'
```

在某些情况下，不同 Consul 服务中可能存在相同服务名。
为避免混淆，推荐在实践中使用完整的 Consul 键路径作为服务名。

### 端口处理

当 APISIX 从 Consul 获取服务信息时，端口处理逻辑如下：

* 如果服务注册中包含有效端口号，则使用该端口
* 如果端口为 `nil` 或 `0`，则默认使用 HTTP 的 80 端口

### Upstream 配置

#### L7

以下是一个将路径为 "/\*" 的请求路由到名为 "service\_a" 且使用 Consul 作为服务发现的 upstream 的示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/*",
    "upstream": {
        "service_name": "service_a",
        "type": "roundrobin",
        "discovery_type": "consul"
    }
}'
```

响应示例如下：

```json
{
  "key": "/apisix/routes/1",
  "value": {
    "uri": "/*",
    "priority": 0,
    "id": "1",
    "upstream": {
      "scheme": "http",
      "type": "roundrobin",
      "hash_on": "vars",
      "discovery_type": "consul",
      "service_name": "service_a",
      "pass_host": "pass"
    },
    "create_time": 1669267329,
    "status": 1,
    "update_time": 1669267329
  }
}
```

你可以在 `apisix/t/discovery/consul.t` 文件中找到更多用例。

#### L4

Consul 服务发现也支持在 L4 中使用，配置方式与 L7 类似。

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
      "scheme": "tcp",
      "service_name": "service_a",
      "type": "roundrobin",
      "discovery_type": "consul"
    }
}'
```

### discovery\_args

| 名称              | 类型     | 是否必需 | 默认值 | 可选值 | 描述                  |
| --------------- | ------ | ---- | --- | --- | ------------------- |
| metadata\_match | object | 可选   | {}  |     | 使用包含匹配的方式按元数据过滤服务实例 |

#### 元数据过滤

APISIX 支持根据元数据过滤服务实例。当路由配置了元数据条件时，只有元数据满足 `metadata_match` 条件的服务实例才会被选中。

示例：服务实例的元数据为 `{lane: "a", env: "prod", version: "1.0"}`，则以下配置匹配成功：`{lane: ["a"]}` 或 `{lane: ["a", "b"], env: "prod"}`，但 `{lane: ["c"]}` 或 `{lane: "a", region: "us"}` 则匹配失败。

带元数据过滤的路由示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithMetadata/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "metadata": {
            "version": ["v1", "v2"]
          }
        }
    }
}'
```

仅路由到带 `version` 字段且值为 `v1` 或 `v2` 的服务实例。

多条件元数据过滤示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/6 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithMultipleMetadata/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "metadata": {
            "lane": ["a"],
            "env": ["prod"]
          }
        }
    }
}'
```

只有同时包含 `lane: "a"` 和 `env: "prod"` 的实例才会被匹配。

更多用法请参考 `apisix/t/discovery/stream/consul.t` 文件。

## 调试接口

提供了调试用的控制接口。

### 内存转储接口

```shell
GET /v1/discovery/consul/dump
```

示例：

```shell
# curl http://127.0.0.1:9090/v1/discovery/consul/dump | jq
{
  "config": {
    "fetch_interval": 3,
    "timeout": {
      "wait": 60,
      "connect": 6000,
      "read": 6000
    },
    "weight": 1,
    "servers": [
      "http://172.19.5.30:8500",
      "http://172.19.5.31:8500"
    ],
    "keepalive": true,
    "default_service": {
      "host": "172.19.5.11",
      "port": 8899,
      "metadata": {
        "fail_timeout": 1,
        "weight": 1,
        "max_fails": 1
      }
    },
    "skip_services": [
      "service_d"
    ]
  },
  "services": {
    "service_a": [
      {
        "host": "127.0.0.1",
        "port": 30513,
        "weight": 1
      },
      {
        "host": "127.0.0.1",
        "port": 30514,
        "weight": 1
      }
    ],
    "service_b": [
      {
        "host": "172.19.5.51",
        "port": 50051,
        "weight": 1
      }
    ],
    "service_c": [
      {
        "host": "127.0.0.1",
        "port": 30511,
        "weight": 1
      },
      {
        "host": "127.0.0.1",
        "port": 30512,
        "weight": 1
      }
    ]
  }
}
```

### 查看转储文件接口

还提供了查看转储文件的控制接口。未来可能添加更多调试 API。

```shell
GET /v1/discovery/consul/show_dump_file
```

示例：

```shell
curl http://127.0.0.1:9090/v1/discovery/consul/show_dump_file | jq
{
  "services": {
    "service_a": [
      {
        "host": "172.19.5.12",
        "port": 8000,
        "weight": 120
      },
      {
        "host": "172.19.5.13",
        "port": 8000,
        "weight": 120
      }
    ]
  },
  "expire": 0,
  "last_update": 1615877468
}
```
