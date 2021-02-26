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

# 目录

- [**插件简介**](#插件简介)
- [**插件属性**](#插件属性)
- [**插件接口**](#插件接口)
- [**启用插件**](#启用插件)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 插件简介

`node-status` 是 `APISIX` 的请求状态查询插件，返回基本的状态信息。

## 插件属性

无。

## 插件接口

插件增加接口 `/apisix/status`，可通过 [interceptors](../plugin-interceptors.md) 保护该接口。

## 启用插件

1. 配置文件 `conf/config.yaml` 的 plugin list 中配置 `node-status`

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```

启动 `APISIX` 之后，即可访问该插件提供的接口，获得基本的状态信息。

2. 在创建 route 时添加插件 `node-status`

```sh
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/route1",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "192.168.1.100:80:": 1
        }
    },
    "plugins": {
        "node-status":{}
    }
}'
```

发送该请求的前提是 `apisix/conf/config.yaml` 中已经配置 `node-status`，此时 `node-status` 插件对该请求处理无影响，所以一般不会将 `node-status` 插件设置到路由中。

## 测试插件

1. 发送请求

```sh
$ curl localhost:9080/apisix/status -i
HTTP/1.1 200 OK
Date: Tue, 03 Nov 2020 11:12:55 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"status":{"total":"23","waiting":"0","accepted":"22","writing":"1","handled":"22","active":"1","reading":"0"},"id":"6790a064-8f61-44ba-a6d3-5df42f2b1bb3"}
```

2. 参数说明

| 参数         | 说明                                         |
| ------------ | -------------------------------------------- |
| status       | 状态信息                                     |
| total        | 客户端请求总数                               |
| waiting      | 当前等待客户端请求的空闲连接数               |
| accepted     | 已经接受的客户端连接总数                         |
| writing      | 当前正在写给客户端响应的连接数               |
| handled      | 已经处理的连接总数,通常等于 accepted          |
| active       | 当前活跃的客户端连接数                       |
| reading      | 当前正在读取请求头的连接数                   |
| id           | APISIX uid 信息，保存在 apisix/conf/apisix.uid  |

## 禁用插件

1. 配置文件 `apisix/conf/config.yaml` 的 plugin list 中删除 `node-status`

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - jwt-auth
  - zipkin
  ......
```

2. 删除 route 中的 `node-status` 插件信息

```sh
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/route1",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "192.168.1.100:80": 1
        }
    },
    "plugins": {}
}'
```
