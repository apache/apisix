---
title: limit-count
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

## 简介

启用该插件后，网关将支持限流能力，在一个固定时间窗口内，超过预设值的请求将被拒绝。

## 参数

|       参数名        |    类型    |                必选                |   默认值    |                                        值范围                                        |                                                              描述                                                               |
| :-----------------: | :--------: | :--------------------------------: | :---------: | :----------------------------------------------------------------------------------: | :-----------------------------------------------------------------------------------------------------------------------------: |
|        count        |   整数型   |                 是                 |             |                                      count > 0                                       |                                                   一个时间窗口内请求数量阈值                                                    |
|     time_window     |   整数型   |                 是                 |             |                                   time_window > 0                                    |                                          时间窗口大小（单位：秒），超过该值就会重置。                                           |
|         key         |   字符串   |                 否                 | remote_addr | remote_addr,server_addr,http_x_real_ip,http_x_forwarded_for,consumer_name,service_id |                                                    用于做请求计数的关键字。                                                     |
|    rejected_code    |   整数型   |                 否                 |     503     |                                      200 ~ 599                                       |                                     当请求数量超过阈值而被网关拒绝时，返回的 HTTP 状态码。                                      |
|       policy        |   字符串   |                 否                 |    local    |                              local,redis,redis-cluster                               | 计数器存放位置策略。local：计数器保存在节点本地内存中；redis：计数器保存在 Redis 节点；redis-cluster：计数器保存在 Redis 集群。 |
|     redis_host      |   字符串   |     当 `policy = redis` 时必选     |             |                                                                                      |                                                         Redis 节点地址                                                          |
|     redis_port      |   整数型   |     当 `policy = redis` 时必选     |    6379     |                                                                                      |                                                         Redis 节点端口                                                          |
|   redis_password    |   字符串   |     当 `policy = redis` 时必选     |             |                                                                                      |                                                         Redis 节点密码                                                          |
|   redis_database    |   整数型   |     当 `policy = redis` 时必选     |      0      |                                         >=0                                          |                                         Redis 节点中 databse，不适用于 redis-cluster。                                          |
| redis_cluster_nodes | 字符串列表 | 当 `policy = redis-clyster` 时必选 |             |                                                                                      |                                                     Redis 集群节点地址列表                                                      |
| redis_cluster_name  |   字符串   | 当 `policy = redis-clyster` 时必选 |             |                                                                                      |                                                       Redis 集群节点名称                                                        |

## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下配置（场景 1）表示：在一个时间窗口（60s）内，若具有相同 `remote_addr` 的请求访问超过 2 次，那么网关将返回 503 状态码。

```bash
# 场景1：使用默认策略（local）

## Request
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "limit-count": {
      "count": 2,
      "time_window": 60,
      "rejected_code": 503,
      "key": "remote_addr"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'

# 场景2：使用 redis 策略

## Request
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "limit-count": {
      "count": 2,
        "time_window": 60,
        "rejected_code": 503,
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "127.0.0.1",
        "redis_port": 6379,
        "redis_password": "password",
        "redis_database": 1,
        "redis_timeout": 1001
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'

# 场景3：使用 redis-cluster 策略

## Request
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "limit-count": {
      "count": 2,
      "time_window": 60,
      "rejected_code": 503,
      "key": "remote_addr",
      "policy": "redis-cluster",
      "redis_cluster_nodes": [
        "127.0.0.1:5000",
        "127.0.0.1:5001"
      ],
      "redis_cluster_name": "redis-cluster-1"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```

接着，在 60s 内访问路由以测试场景 1：

```bash
# 第1次访问：
## Request
$ curl -i http://127.0.0.1:9080/get

## Response
...
HTTP/1.1 200 OK
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
...

# 第2次访问：
## Request
$ curl -i http://127.0.0.1:9080/get

## Response
...
HTTP/1.1 200 OK
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
...

# 第3次访问：
## Request
$ curl -i http://127.0.0.1:9080/get

## Response
...
HTTP/1.1 503 Service Temporarily Unavailable
...

```

每次访问时，响应头中将包含 `X-RateLimit-Limit` 与 `X-RateLimit-Remaining`，分别表示允许的最大请求次数与当前可用次数。

## 使用 AdminAPI 禁用插件

如果希望禁用插件，只需更新路由配置，从 plugins 字段移除该插件即可：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```
