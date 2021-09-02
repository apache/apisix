---
title: proxy-mirror
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

代理镜像插件，该插件提供了镜像客户端请求的能力。

注：镜像请求返回的响应会被忽略。

### 参数

| 名称 | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                    |
| ---- | ------ | ------ | ------ | ------ | ------------------------------------------------------------------------------------------------------- |
| host | string | 必须   |        |        | 指定镜像服务地址，例如：http://127.0.0.1:9797（地址中需要包含 schema ：http或https，不能包含 URI 部分） |
| enable_limit_count               | boolean | 可选                                | false              |                                                                                                | 是否启用镜像请求数限制。                                                                                                                                                                                                                                                                |
| count               | integer | 可选                               | 1              | count > 0                                                                                               | 指定时间窗口内的镜像请求数量阈值                                                                                                                                                                                                                                                                                                                                                                                          |
| time_window         | integer | 可选                               | 60              | time_window > 0                                                                                         | 时间窗口的大小（以秒为单位），超过这个时间就会重置                                                                                                                                                                                                                                                                                                                                                                    |
| policy              | string  | 可选                               | "local"       | ["local", "redis", "redis-cluster"]                                                                     | 用于检索和增加限制的镜像请求数限制策略。可选的值有：`local`(计数器被以内存方式保存在节点本地，默认选项) 和 `redis`(计数器保存在 Redis 服务节点上，从而可以跨节点共享结果，通常用它来完成全局限速)；以及`redis-cluster`，跟 redis 功能一样，只是使用 redis 集群方式。                                                                                                                                                        |
| redis_host          | string  | `redis` 必须                       |               |                                                                                                         | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点的地址。                                                                                                                                                                                                                                                                                                                                                            |
| redis_port          | integer | 可选                               | 6379          | [1,...]                                                                                                 | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点的端口                                                                                                                                                                                                                                                                                                                                                              |
| redis_password      | string  | 可选                               |               |                                                                                                         | 当使用 `redis`  或者 `redis-cluster`  限速策略时，该属性是 Redis 服务节点的密码。                                                                                                                                                                                                                                                                                                                                                            |
| redis_database      | integer | 可选                               | 0             | redis_database >= 0                                                                                     | 当使用 `redis` 限速策略时，该属性是 Redis 服务节点中使用的 database，并且只针对非 Redis 集群模式（单实例模式或者提供单入口的 Redis 公有云服务）生效。                                                                                                                                                                                                                                                                 |
| redis_timeout       | integer | 可选                               | 1000          | [1,...]                                                                                                 | 当使用 `redis`  或者 `redis-cluster`  限速策略时，该属性是 Redis 服务节点以毫秒为单位的超时时间                                                                                                                                                                                                                                                                                                                                              |
| redis_cluster_nodes | array   | 当 policy 为 `redis-cluster` 时必填|               |                                                                                                         | 当使用 `redis-cluster` 限速策略时，该属性是 Redis 集群服务节点的地址列表（至少需要两个地址）。                                                                                                                                                                                                                                                                                                                                            |
| redis_cluster_name  | string  | 当 policy 为 `redis-cluster` 时必填 |               |                                                                                                         | 当使用 `redis-cluster` 限速策略时，该属性是 Redis 集群服务节点的名称。                                                                                                                                                                                                                                                                                                                                            |

### 示例

#### 启用插件

示例1：为特定路由启用 `proxy-mirror` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 12
Connection: keep-alive
Server: APISIX web server
Date: Wed, 18 Mar 2020 13:01:11 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT

hello world
```

> 由于指定的 mirror 地址是127.0.0.1:9797，所以验证此插件是否已经正常工作需要在端口为9797的服务上确认，例如，我们可以通过 python 启动一个简单的 server： python -m SimpleHTTPServer 9797。

示例2：为特定路由启用 `proxy-mirror` 插件，并且启用镜像请求数限制：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797",
            "enable_limit_count": true,
            "count": 2,
            "time_window": 60
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

在此例子中，60 秒内仅允许两个镜像请求。

#### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1999": 1
        }
    }
}'
```

这时该插件已被禁用。
