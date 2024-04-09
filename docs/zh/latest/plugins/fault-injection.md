---
title: fault-injection
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Fault Injection
  - fault-injection
description: 本文介绍了关于 Apache APISIX `fault-injection` 插件的基本信息及使用方法。
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

`fault-injection` 插件是故障注入插件，该插件可以和其他插件一起使用，并在其他插件执行前被执行。

## 属性

| 名称              | 类型    | 必选项 | 有效值     | 描述                       |
| ----------------- | ------- | ---- |  ---------- | -------------------------- |
| abort.http_status | integer | 是   |  [200, ...] | 返回给客户端的 HTTP 状态码 |
| abort.body        | string  | 否   |             | 返回给客户端的响应数据。支持使用 NGINX 变量，如 `client addr: $remote_addr\n`|
| abort.headers     | object  | 否   |            |  返回给客户端的响应头，可以包含 NGINX 变量，如 `$remote_addr` |
| abort.percentage  | integer | 否   |  [0, 100]   | 将被中断的请求占比         |
| abort.vars        | array[] | 否   |             | 执行故障注入的规则，当规则匹配通过后才会执行故障注。`vars` 是一个表达式的列表，来自 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。 |
| delay.duration    | number  | 是   |             | 延迟时间，可以指定小数     |
| delay.percentage  | integer | 否   |  [0, 100]   | 将被延迟的请求占比         |
| delay.vars        | array[] | 否   |             | 执行请求延迟的规则，当规则匹配通过后才会延迟请求。`vars` 是一个表达式列表，来自 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。   |

:::info IMPORTANT

`abort` 属性将直接返回给客户端指定的响应码并且终止其他插件的执行。

`delay` 属性将延迟某个请求，并且还会执行配置的其他插件。

`abort` 和 `delay` 属性至少要配置一个。

:::

:::tip

`vars` 是由 [`lua-resty-expr`](https://github.com/api7/lua-resty-expr) 的表达式组成的列表，它可以灵活的实现规则之间的 AND/OR 关系，示例如下：：

```json
[
    [
        [ "arg_name","==","jack" ],
        [ "arg_age","==",18 ]
    ],
    [
        [ "arg_name2","==","allen" ]
    ]
]
```

以上示例表示前两个表达式之间的关系是 AND，而前两个和第三个表达式之间的关系是 OR。

:::

## 启用插件

你可以在指定路由启用 `fault-injection` 插件，并指定 `abort` 属性。如下所示：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "abort": {
              "http_status": 200,
              "body": "Fault Injection!"
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

同样，我们也可以指定 `delay` 属性。如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "delay": {
              "duration": 3
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

还可以同时为指定路由启用 `fault-injection` 插件，并指定 `abort` 属性和 `delay` 属性的 `vars` 规则。如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                "http_status": 403,
                "body": "Fault Injection!\n",
                "vars": [
                    [
                        [ "arg_name","==","jack" ]
                    ]
                ]
            },
            "delay": {
                "duration": 2,
                "vars": [
                    [
                        [ "http_age","==","18" ]
                    ]
                ]
            }
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

## 测试插件

通过上述示例启用插件后，可以向路由发起如下请求：

```shell
curl http://127.0.0.1:9080/hello -i
```

```shell
HTTP/1.1 200 OK
Date: Mon, 13 Jan 2020 13:50:04 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

Fault Injection!
```

通过如下命令可以向配置 `delay` 属性的路由发起请求：

```shell
time curl http://127.0.0.1:9080/hello -i
```

```shell
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 6
Connection: keep-alive
Server: APISIX web server
Date: Tue, 14 Jan 2020 14:30:54 GMT
Last-Modified: Sat, 11 Jan 2020 12:46:21 GMT

hello

real    0m3.034s
user    0m0.007s
sys     0m0.010s
```

### 标准匹配的故障注入

你可以在 `fault-injection` 插件中使用 `vars` 规则设置特定规则：

```Shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                    "http_status": 403,
                    "body": "Fault Injection!\n",
                    "vars": [
                        [
                            [ "arg_name","==","jack" ]
                        ]
                    ]
            }
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

使用不同的 `name` 参数测试路由：

```Shell
curl "http://127.0.0.1:9080/hello?name=allen" -i
```

没有故障注入的情况下，你可以得到如下结果：

```shell
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 07:21:57 GMT
Server: APISIX/2.2

hello
```

如果我们将 `name` 设置为与配置相匹配的名称，`fault-injection` 插件将被执行：

```Shell
curl "http://127.0.0.1:9080/hello?name=jack" -i
```

```shell
HTTP/1.1 403 Forbidden
Date: Wed, 20 Jan 2021 07:23:37 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!
```

## 删除插件

当你需要禁用 `fault-injection` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
