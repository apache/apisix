---
title: consumer-restriction
keywords:
  - Apache APISIX
  - API 网关
  - Consumer restriction
description: Consumer Restriction 插件允许用户根据 Route、Service、Consumer 或 Consumer Group 来设置相应的访问限制。
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

`consumer-restriction` 插件允许用户根据 Route、Service、Consumer 或 Consumer Group 来设置相应的访问限制。

## 属性

| 名称                       | 类型          | 必选项 | 默认值        | 有效值                                                       | 描述                                                         |
| -------------------------- | ------------- | ------ | ------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| type                       | string        | 否     | consumer_name | ["consumer_name", "consumer_group_id", "service_id", "route_id"] | 支持设置访问限制的对象类型。                                 |
| whitelist                  | array[string] | 是     |               |                                                              | 加入白名单的对象，优先级高于`allowed_by_methods`。           |
| blacklist                  | array[string] | 是     |               |                                                              | 加入黑名单的对象，优先级高于`whitelist`。                    |
| rejected_code              | integer       | 否     | 403           | [200,...]                                                    | 当请求被拒绝时，返回的 HTTP 状态码。                         |
| rejected_msg               | string        | 否     |               |                                                              | 当请求被拒绝时，返回的错误信息。                             |
| allowed_by_methods         | array[object] | 否     |               |                                                              | 一组为 Consumer 设置允许的配置，包括用户名和允许的 HTTP 方法列表。 |
| allowed_by_methods.user    | string        | 否     |               |                                                              | 为 Consumer 设置的用户名。                                   |
| allowed_by_methods.methods | array[string] | 否     |               | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE", "PURGE"] | 为 Consumer 设置的允许的 HTTP 方法列表。                     |

:::note

不同的 `type` 属性值分别代表以下含义：

- `consumer_name`：把 Consumer 的 `username` 列入白名单或黑名单来限制 Consumer 对 Route 或 Service 的访问。
- `consumer_group_id`: 把 Consumer Group 的 `id` 列入白名单或黑名单来限制 Consumer 对 Route 或 Service 的访问。
- `service_id`：把 Service 的 `id` 列入白名单或黑名单来限制 Consumer 对 Service 的访问，需要结合授权插件一起使用。
- `route_id`：把 Route 的 `id` 列入白名单或黑名单来限制 Consumer 对 Route 的访问。

:::

## 启用并测试插件

### 通过 `consumer_name` 限制访问

首先，创建两个 Consumer，分别为 `jack1` 和 `jack2`：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "username": "jack1",
    "plugins": {
        "basic-auth": {
            "username":"jack2019",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "username": "jack2",
    "plugins": {
        "basic-auth": {
            "username":"jack2020",
            "password": "123456"
        }
    }
}'
```

然后，在指定路由上启用并配置 `consumer-restriction` 插件，并通过将 `consumer_name` 加入 `whitelist` 来限制不同 Consumer 的访问：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

`jack1` 发出访问请求，返回 `200` HTTP 状态码，代表访问成功：

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 200 OK
```

`jack2` 发出访问请求，返回 `403` HTTP 状态码，代表访问被限制，插件生效：

```shell
curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

### 通过 `allowed_by_methods` 限制访问

首先，创建两个 Consumer，分别为 `jack1` 和 `jack2`，创建方法请参考[通过 `consumer_name` 限制访问](#通过-consumername-限制访问)。

然后，在指定路由上启用并配置 `consumer-restriction` 插件，并且仅允许 `jack1` 使用 `POST` 方法进行访问：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
            "allowed_by_methods":[{
                "user": "jack1",
                "methods": ["POST"]
            }]
        }
    }
}'
```

**测试插件**

`jack1` 发出访问请求，返回 `403` HTTP 状态码，代表访问被限制：

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

现在更新插件配置，增加 `jack1` 的 `GET` 访问能力：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
            "allowed_by_methods":[{
                "user": "jack1",
                "methods": ["POST","GET"]
            }]
        }
    }
}'
```

`jack1` 再次发出访问请求，返回 `200` HTTP 状态码，代表访问成功：

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 200 OK
```

### 通过 `service_id` 限制访问

使用 `service_id` 的方式需要与授权插件一起配合使用，这里以 [`key-auth`](./key-auth.md) 授权插件为例。

首先，创建两个 Service：

```shell
curl http://127.0.0.1:9180/apisix/admin/services/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 001"
}'

curl http://127.0.0.1:9180/apisix/admin/services/2 -H "X-API-KEY: $admin_key" -X PUT -d '
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

在指定 Consumer 上配置 `key-auth` 和 `consumer-restriction` 插件，并通过将 `service_id` 加入 `whitelist` 来限制 Consumer 对 Service 的访问：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
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

**测试插件**

在指定路由上启用并配置 `key-auth` 插件，并绑定 `service_id` 为 `1`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

对 Service 发出访问请求，返回 `403` HTTP 状态码，说明在白名单列中的 `service_id` 允许访问，插件生效：

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
```

```shell
HTTP/1.1 200 OK
```

更新配置 `key-auth` 插件，并绑定 `service_id` 为 `2`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

再次对 Service 发出访问请求，返回 `403` HTTP 状态码，说明不在白名单列表的 `service_id` 被拒绝访问，插件生效：

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The service_id is forbidden."}
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
