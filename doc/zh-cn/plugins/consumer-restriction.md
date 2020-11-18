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

- [English](../../plugins/consumer-restriction.md)

# 目录
  - [简介](#简介)
  - [属性](#属性)
  - [示例](#示例)
    - [如何限制 consumer_name](#如何限制-consumer_name)
    - [如何限制 service_id](#如何限制-service_id)
  - [禁用插件](#禁用插件)

## 简介

`consumer-restriction` 根据选择的不同对象做相应的访问限制。

## 属性

| 参数名     | 类型          | 可选项   | 默认值            | 有效值                           | 描述                                                       |
| --------- | ------------- | ------ | -----------------| --------------------------------| ----------------------------------------------------------|
| type      |     string    | 可选    | consumer_name    | ["consumer_name", "service_id"] | 根据不同的对象做相应的限制,支持 `consumer_name`、`service_id`。     |
| whitelist | array[string] | 必选    |                  |                                 | 与`blacklist`二选一，只能单独启用白名单或黑名单，两个不能一起使用。 |
| blacklist | array[string] | 必选    |                  |                                 | 与`whitelist`二选一，只能单独启用白名单或黑名单，两个不能一起使用。 |
| rejected_code | integer   | 可选    | 403              | [200,...]                       | 当请求被拒绝时，返回的 HTTP 状态码。|

对于 `type` 字段是个枚举类型，它可以是 `consumer_name` 或 `service_id` 。分别代表以下含义：
* **consumer_name**：把 `consumer` 的 `username` 列入白名单或黑名单（支持单个或多个 consumer）来限制对服务或路线的访问。
* **service_id**：把 `service` 的 `id` 列入白名单或黑名单（支持一个或多个 service）来限制service的访问，需要结合授权插件一起使用。

## 示例

### 如何限制 `consumer_name`

下面是一个示例，在指定的 route 上开启了 `consumer-restriction` 插件，限制 consumer 访问:

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

**测试插件**

jack1 访问:

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
...
```

jack2 访问:

```shell
curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

### 如何限制 `service_id`
`service_id`方式需要与授权插件一起配合使用，这里以key-auth授权插件为例。

1、创建两个 service

```shell
curl http://127.0.0.1:9080/apisix/admin/services/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 001"
}'

curl http://127.0.0.1:9080/apisix/admin/services/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 002"
}'
```

2、在 `consumer` 上绑定 `consumer-restriction` 插件(需要与一个授权插件配合才能绑定),并添加 `service_id` 白名单列表

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "new_consumer",
    "plugins": {
    "key-auth": {
        "key": "auth-jack"
    },
    "consumer-restriction": {
           "type": "service_id",
            "whitelist": [
                "1"
            ],
            "rejected_code": 403
        }
    }
}'
```

3、在 route 上开启 `key-auth` 插件并绑定 `service_id` 为`1`

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "service_id": 1,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

**测试插件**

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
HTTP/1.1 200 OK
...
```

说明在白名单列中的 `service_id` 允许访问，插件配置生效。

4、在 route 上开启 `key-auth` 插件并绑定 `service_id` 为`2`

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "service_id": 2,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

**测试插件**

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
HTTP/1.1 403 Forbidden
...
{"message":"The service_id is forbidden."}
```

说明不在白名单列表的 `service_id` 被拒绝访问，插件配置生效。

## 禁用插件

当你想去掉 `consumer-restriction` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
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
        "basic-auth": {}
    }
}'
```

现在就已移除 `consumer-restriction` 插件，其它插件的开启和移除也类似。
