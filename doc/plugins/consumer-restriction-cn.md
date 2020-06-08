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

[English](consumer-restriction.md)

# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`consumer-restriction` 可以通过以下方式限制对服务或路线的访问，将 consumer 列入白名单或黑名单。 支持单个或多个 consumer。

## 属性

* `whitelist`: 可选，加入白名单的consumer
* `blacklist`: 可选，加入黑名单的consumer

只能单独启用白名单或黑名单，两个不能一起使用。

## 如何启用

下面是一个示例，在指定的 route 上开启了 `consumer-restriction` 插件，限制consumer访问:


```shell
curl http://127.0.0.1:9080/apisix/admin/consumers/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack1",
    "plugins": {
        "basic-auth": {
            "username":"jack2019",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/consumers/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack2",
    "plugins": {
        "basic-auth": {
            "username":"jack2020",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {},
        "consumer-restriction": {
            "whitelist": [
                "jack1"
            ]
        }
    }
}'
```

## 测试插件

jack1 访问:

```shell
$ curl -u jack2019:123456 http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

jack2 访问:

```shell
$ curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"You are not allowed"}
```

## 禁用插件

当你想去掉 `consumer-restriction` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {}
    }
}'
```

现在就已移除 `consumer-restriction` 插件，其它插件的开启和移除也类似。

