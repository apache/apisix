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

## 描述

和 [GitHub API 的限速](https://docs.github.com/en/rest/reference/rate-limit) 类似，
在指定的时间范围内，限制总的请求个数。并且在 HTTP 响应头中返回剩余可以请求的个数。

## 属性

| 名称                | 类型    | 必选项                               | 默认值        | 有效值                                                                                                  | 描述                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------- | ------- | --------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count               | integer | 必须                               |               | count > 0                                                                                               | 指定时间窗口内的请求数量阈值                                                                                                                                                                                                                                                                                                                                                                                          |
| time_window         | integer | 必须                               |               | time_window > 0                                                                                         | 时间窗口的大小（以秒为单位），超过这个时间就会重置                                                                                                                                                                                                                                                                                                                                                                    |
| key_type      | string | 可选   |  "var"      | ["var", "var_combination", "constant"]                                          | key 的类型 |
| key           | string  | 可选   |    "remote_addr"    |  | 用来做请求计数的依据。如果 `key_type` 为 "constant"，那么 key 会被当作常量。如果 `key_type` 为 "var"，那么 key 会被当作变量名称。如果 `key_type` 为 "var_combination"，那么 key 会当作变量组。比如如果设置 "$remote_addr $consumer_name" 作为 key，那么插件会同时受 remote_addr 和 consumer_name 两个变量的约束。如果 key 的值为空，$remote_addr 会被作为默认 key。 |
| rejected_code       | integer | 可选                               | 503           | [200,...,599]                                                                                           | 当请求超过阈值被拒绝时，返回的 HTTP 状态码                                                                                                                                                                                                                                                                                                                                                                            |
| rejected_msg       | string | 可选                                |            | 非空                                                                                           | 当请求超过阈值被拒绝时，返回的响应体。                                                                                                                                                                                                             |
| policy              | string  | 可选                               | "local"       | ["local", "redis", "redis-cluster"]                                                                     | 用于检索和增加限制的速率限制策略。可选的值有：`local`(计数器被以内存方式保存在节点本地，默认选项) 和 `redis`(计数器保存在 Redis 服务节点上，从而可以跨节点共享结果，通常用它来完成全局限速)；以及`redis-cluster`，跟 redis 功能一样，只是使用 redis 集群方式。                                                                                                                                                        |
| allow_degradation              | boolean  | 可选                                | false       |                                                                     | 当限流插件功能临时不可用时（例如，Redis 超时）是否允许请求继续。当值设置为 true 时则自动允许请求继续，默认值是 false。|
| show_limit_quota_header              | boolean  | 可选                                | true       |                                                                     | 是否在响应头中显示 `X-RateLimit-Limit` 和 `X-RateLimit-Remaining`（限制的总请求数和剩余还可以发送的请求数），默认值是 true。 |
| group               | string | 可选                                |            | 非空                                                                                           | 配置同样的 group 的 Route 将共享同样的限流计数器 |
| redis_host          | string  | `redis` 必须                       |               |                                                                                                         | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点的地址。                                                                                                                                                                                                                                                                                                                                                            |
| redis_port          | integer | 可选                               | 6379          | [1,...]                                                                                                 | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点的端口                                                                                                                                                                                                                                                                                                                                                              |
| redis_password      | string  | 可选                               |               |                                                                                                         | 当使用 `redis`  或者 `redis-cluster`  限速策略时，该属性是 Redis 服务节点的密码。                                                                                                                                                                                                                                                                                                                                                            |
| redis_database      | integer | 可选                               | 0             | redis_database >= 0                                                                                     | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点中使用的 database，并且只针对非 Redis 集群模式（单实例模式或者提供单入口的 Redis 公有云服务）生效。                                                                                                                                                                                                                                                                 |
| redis_timeout       | integer | 可选                               | 1000          | [1,...]                                                                                                 | 当使用 `redis` 或者 `redis-cluster` 限速策略时，该属性是 Redis 服务节点以毫秒为单位的超时时间                                                                                                                                                                                                                                                                                                                                              |
| redis_cluster_nodes | array   | 当 policy 为 `redis-cluster` 时必填 |               |                                                                                                         | 当使用 `redis-cluster` 限速策略时，该属性是 Redis 集群服务节点的地址列表（至少需要两个地址）。                                                                                                                                                                                                                                                                                                                                            |
| redis_cluster_name  | string  | 当 policy 为 `redis-cluster` 时必填 |               |                                                                                                         | 当使用 `redis-cluster` 限速策略时，该属性是 Redis 集群服务节点的名称。                                                                                                                                                                                                                                                                                                                                            |

## 如何使用

### 开启插件

下面是一个示例，在指定的 `route` 上开启了 `limit count` 插件，并设置 `key_type` 为 `var`：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

下面是一个示例，在指定的 `route` 上开启了 `limit count` 插件，并设置 `key_type` 为 `var_combination`：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:9001": 1
        }
    }
}'
```

你也可以通过 web 界面来完成上面的操作，先增加一个 route，然后在插件页面中添加 limit-count 插件：
![添加插件](../../../assets/images/plugin/limit-count-1.png)

我们也支持在多个 Route 间共享同一个限流计数器。举个例子，

```shell
curl -i http://127.0.0.1:9080/apisix/admin/services/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "group": "services_1#1640140620"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

每个配置了 `group` 为 `services_1#1640140620` 的 Route 都将共享同一个每个 IP 地址每分钟只能访问一次的计数器。

```shell
$ curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello"
}'

$ curl -i http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello2"
}'

$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 ...

$ curl -i http://127.0.0.1:9080/hello2
HTTP/1.1 503 ...
```

注意同一个 group 里面的 limit-count 配置必须一样。
所以，一旦修改了配置，我们需要更新对应的 group 的值。

我们也支持在所有请求间共享同一个限流计数器。举个例子，

```shell
curl -i http://127.0.0.1:9080/apisix/admin/services/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "key_type": "constant",
            "group": "services_1#1640140621"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

在上面的例子中，我们将 `key_type` 设置为 `constant`。
通过设置 `key_type` 为 `constant`，`key` 的值将会直接作为常量来处理。

现在每个配置了 `group` 为 `services_1#1640140620` 的 Route 上的所有请求，都将共享同一个每分钟只能访问一次的计数器，即使它们来自不同的 IP 地址。

如果你需要一个集群级别的流量控制，我们可以借助 redis server 来完成。不同的 APISIX 节点之间将共享流量限速结果，实现集群流量限速。

如果启用单 redis 策略，请看下面例子：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
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
            "127.0.0.1:1980": 1
        }
    }
}'
```

如果使用 `redis-cluster` 策略：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
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
            "redis_password": "password",
            "redis_cluster_name": "redis-cluster-1"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

上述配置限制了 60 秒内只能访问 2 次，前两次访问都会正常访问：

```shell
curl -i http://127.0.0.1:9080/index.html
```

响应头里面包含了 `X-RateLimit-Limit` 和 `X-RateLimit-Remaining`，他们的含义分别是限制的总请求数和剩余还可以发送的请求数：

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
Server: APISIX web server
```

当你第三次访问的时候，就会收到包含 503 返回码的响应头：

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

同时，如果你设置了属性 `rejected_msg` 的值为 `"Requests are too frequent, please try again later."` ，当你第三次访问的时候，就会收到如下的响应体：

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

{"error_msg":"Requests are too frequent, please try again later."}
```

这就表示 `limit count` 插件生效了。

## 移除插件

当你想去掉 `limit count` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

现在就已经移除了 `limit count` 插件了。其他插件的开启和移除也是同样的方法。
