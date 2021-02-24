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

# fault-injection

故障注入插件，该插件可以和其他插件一起使用，并且会在其他插件前被执行，配置 `abort` 参数将直接返回给客户端指定的响应码并且终止其他插件的执行，配置 `delay` 参数将延迟某个请求，并且还会执行配置的其他插件。

## 参数

| 名称              | 类型    | 必选项 | 默认值 | 有效值     | 描述                       |
| ----------------- | ------- | ------ | ------ | ---------- | -------------------------- |
| abort.http_status | integer | 必需   |        | [200, ...] | 返回给客户端的 http 状态码 |
| abort.body        | string  | 可选   |        |            | 返回给客户端的响应数据。支持使用 Nginx 变量，如 `client addr: $remote_addr\n`|
| abort.percentage  | integer | 可选   |        | [0, 100]   | 将被中断的请求占比         |
| abort.vars        | array[] | 可选   |        |            | 执行故障注入的规则，当规则匹配通过后才会执行故障注。`vars` 是一个表达式的列表，来自 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。 |
| delay.duration    | number  | 必需   |        |            | 延迟时间，可以指定小数     |
| delay.percentage  | integer | 可选   |        | [0, 100]   | 将被延迟的请求占比         |
| delay.vars        | array[] | 可选   |        |            | 执行请求延迟的规则，当规则匹配通过后才会延迟请求。`vars` 是一个表达式列表，来自 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。   |

注：参数 abort 和 delay 至少要存在一个。

`vars` 是由 `lua-resty-expr` 的表达式组成的列表，它可以灵活的实现规则之间的 `and/or` 关系，示例：

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

这表示前两个表达式之间的关系是 `and` ，而前两个和第三个表达式之间的关系是 `or`。

## 示例

### 启用插件

示例1：为特定路由启用 `fault-injection` 插件，并指定 `abort` 参数：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Date: Mon, 13 Jan 2020 13:50:04 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

Fault Injection!
```

> http status 返回`200`并且响应`body`为`Fault Injection!`，表示该插件已启用。

示例2：为特定路由启用 `fault-injection` 插件，并指定 `delay` 参数：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

测试：

```shell
$ time curl http://127.0.0.1:9080/hello -i
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

示例3：为特定路由启用 `fault-injection` 插件，并指定 abort 参数的 vars 规则。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

测试：

1、vars 规则匹配失败，请求返回上游响应数据：

```shell
$ curl "http://127.0.0.1:9080/hello?name=allen" -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 07:21:57 GMT
Server: APISIX/2.2

hello
```

2、vars 规则匹配成功，执行故障注入：

```shell
$ curl "http://127.0.0.1:9080/hello?name=jack" -i
HTTP/1.1 403 Forbidden
Date: Wed, 20 Jan 2021 07:23:37 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!
```

示例4：为特定路由启用 `fault-injection` 插件，并指定 delay 参数的 vars 规则。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "delay": {
                "duration": 2,
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

测试：

1、vars 规则匹配失败，不延迟请求：

```shell
$ time "curl http://127.0.0.1:9080/hello?name=allen" -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 07:26:17 GMT
Server: APISIX/2.2

hello

real    0m0.007s
user    0m0.003s
sys     0m0.003s
```

2、vars 规则匹配成功，延迟请求两秒：

```shell
$ time curl "http://127.0.0.1:9080/hello?name=jack" -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 07:57:50 GMT
Server: APISIX/2.2

hello

real    0m2.009s
user    0m0.004s
sys     0m0.004s
```

示例5：为特定路由启用 `fault-injection` 插件，并指定 abort 和 delay 参数的 vars 规则。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

测试：

1、abort 和 delay 的 vars 规则匹配失败：

```shell
$ time curl "http://127.0.0.1:9080/hello?name=allen" -H 'age: 20' -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 08:01:43 GMT
Server: APISIX/2.2

hello

real    0m0.007s
user    0m0.003s
sys     0m0.003s
```

2、abort 的 vars 规则匹配失败，不执行故障注入，但延迟请求：

```shell
$ time curl "http://127.0.0.1:9080/hello?name=allen" -H 'age: 18' -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 08:19:03 GMT
Server: APISIX/2.2

hello

real    0m2.009s
user    0m0.001s
sys     0m0.006s
```

3、delay 的 vars 规则匹配失败，不延迟请求，但执行故障注入：

```shell
$ time curl "http://127.0.0.1:9080/hello?name=jack" -H 'age: 20' -i
HTTP/1.1 403 Forbidden
Date: Wed, 20 Jan 2021 08:20:18 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!

real    0m0.007s
user    0m0.002s
sys     0m0.004s
```

4、abort 和 delay 参数的 vars 规则匹配成功，执行故障注入，并延迟请求：

```shell
$ time curl "http://127.0.0.1:9080/hello?name=jack" -H 'age: 18' -i
HTTP/1.1 403 Forbidden
Date: Wed, 20 Jan 2021 08:21:17 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!

real    0m2.006s
user    0m0.001s
sys     0m0.005s
```

示例6：为特定路由启用 `fault-injection` 插件，并指定 abort 参数的 vars 规则（`or` 的关系）。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                "http_status": 403,
                "body": "Fault Injection!\n",
                "vars": [
                    [
                        ["arg_name","==","jack"],
                        ["arg_age","!","<",18]
                    ],
                    [
                        ["http_apikey","==","apisix-key"]
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

表示当请求参数 name 和 age 同时满足 `name == "jack"`、`age >= 18` 时，执行故障注入。或请求头 apikey 满足 `apikey == "apisix-key"` 时，执行故障注入。

测试：

1、请求参数 name 和 age 匹配成功，缺少请求头 `apikey`， 执行故障注入：

```shell
$ curl "http://127.0.0.1:9080/hello?name=jack&age=19" -i
HTTP/1.1 403 Forbidden
Date: Fri, 22 Jan 2021 11:05:46 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!
```

2、请求头 `apikey` 匹配成功，缺少请求参数，执行故障注入：

```shell
$ curl http://127.0.0.1:9080/hello -H "apikey: apisix-key" -i
HTTP/1.1 403 Forbidden
Date: Fri, 22 Jan 2021 11:08:34 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!
```

3、请求参数与请求头都匹配失败，不执行故障注入：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Fri, 22 Jan 2021 11:11:17 GMT
Server: APISIX/2.2

hello
```

### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

这时该插件已被禁用。
