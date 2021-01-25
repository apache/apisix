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

- [中文](../zh-cn/plugins/fault-injection.md)

## Name

Fault injection plugin, this plugin can be used with other plugins and will be executed before other plugins.  The `abort` attribute will directly return the user-specified http code to the client and terminate the subsequent plugins. The `delay` attribute will delay a request and execute subsequent plugins.

## Attributes

| Name              | Type    | Requirement | Default | Valid      | Description                                      |
| ----------------- | ------- | ----------- | ------- | ---------- | ------------------------------------------------ |
| abort.http_status | integer | required    |         | [200, ...] | user-specified http code returned to the client. |
| abort.body        | string  | optional    |         |            | response data returned to the client. Nginx variable can be used inside, like `client addr: $remote_addr\n`           |
| abort.percentage  | integer | optional    |         | [0, 100]   | percentage of requests to be aborted.            |
| abort.vars        | array[] | optional    |         |            | The rules for executing fault injection will only be executed when the rules are matched. `vars` is a list of expressions, which is from the [lua-resty-expr](https://github.com/api7/lua-resty-expr). |
| delay.duration    | number  | required    |         |            | delay time (can be decimal).                     |
| delay.percentage  | integer | optional    |         | [0, 100]   | percentage of requests to be delayed.            |
| delay.vars        | array[] | optional    |         |            | Execute the request delay rule, and the request will be delayed only after the rule matches. `vars` is a list of expressions, which is from the [lua-resty-expr](https://github.com/api7/lua-resty-expr). |

Note: One of `abort` and `delay` must be specified.

The `vars` is a list of expression which is from the `lua-resty-expr`, which can flexibly implement the `and/or` relationship between rules. Example:

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

This means that the relationship between the first two expressions is `and`, and the relationship between the first two expressions and the third expression is `or`.

## How To Enable

### Enable the plugin

1: enable the fault-injection plugin for a specific route and specify the abort attribute：

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

Test plugin：

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

> http status is 200 and the response body is "Fault Injection! " indicate that the plugin is enabled.

2: Enable the `fault-injection` plugin for a specific route and specify the `delay` attribute:

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

Test plugin：

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

Example 3: Enable the `fault-injection` plugin for a specific route and specify the vars rule of the abort parameter.

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

Test plugin：

1. The vars rule fails to match, and the request returns upstream response data:

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

2. The vars rule is successfully matched and fault injection is performed:

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

Example 4: Enable the `fault-injection` plugin for a specific route and specify the vars rule for the delay parameter.

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

Test plugin：

1. The vars rule fails to match and the request is not delayed:

```shell
$ time curl "http://127.0.0.1:9080/hello?name=allen" -i
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

2. The vars rule is successfully matched, and the request is delayed for two seconds:

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

Example 5: Enable the `fault-injection` plugin for a specific route, and specify the vars rules for the abort and delay parameters.

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

Test plugin：

1. The vars rules of abort and delay fail to match:

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

2. The abort vars rule fails to match, no fault injection is performed, but the request is delayed:

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

3. The vars rule of delay fails to match, the request is not delayed, but fault injection is performed:

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

4. The vars rules of abort and delay parameters match successfully, perform fault injection, and delay the request:

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

Example 6: Enable the `fault-injection` plugin for a specific route, and specify the vars rule of the abort parameter (the relationship of `or`).

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

Indicates that when the request parameters name and age satisfy both `name == "jack"` and `age >= 18`, fault injection is performed. Or when the request header apikey satisfies `apikey == "apisix-key"`, fault injection is performed.

Test plugin：

1. The request parameter name and age match successfully, and the request header `apikey` is missing, and fault injection is performed:

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

2. The request header `apikey` is successfully matched, and the request parameters are missing, and fault injection is performed:

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

3. Both request parameters and request headers fail to match, and fault injection is not performed:

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

## Disable Plugin

Remove the corresponding JSON in the plugin configuration to disable the plugin immediately without restarting the service:

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

The plugin has been disabled now.
