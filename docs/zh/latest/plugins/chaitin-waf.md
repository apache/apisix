---
title: chaitin-waf
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - WAF
description: 本文介绍了关于 Apache APISIX `chaitin-waf` 插件的基本信息及使用方法。
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

在启用 `chaitin-waf` 插件后，流量将可以被转发到长亭 WAF 服务，可以保护请求使其免于受到黑客的攻击。

## 响应头

根据插件配置，可以选择是否附加额外的响应头。

响应头的信息如下：

- **X-APISIX-CHAITIN-WAF**：APISIX 是否将请求转发给 WAF 服务器。
    - yes：转发
    - no：不转发
    - unhealthy：符合匹配条件，但没有可用的 WAF 服务器
    - err：插件执行过程中出错。此时会附带 **X-APISIX-CHAITIN-WAF-ERROR** 请求头
    - waf-err：与 WAF 服务器交互时出错。此时会附带 **X-APISIX-CHAITIN-WAF-ERROR** 请求头
    - timeout：与 WAF 服务器的交互超时
- **X-APISIX-CHAITIN-WAF-ERROR**：调试用响应头。APISIX 与 WAF 交互时的错误信息。
- **X-APISIX-CHAITIN-WAF-TIME**：APISIX 与 WAF 交互所耗费的时间，单位是毫秒。
- **X-APISIX-CHAITIN-WAF-STATUS**：WAF 服务器返回给 APISIX 的状态码。
- **X-APISIX-CHAITIN-WAF-ACTION**：WAF 服务器返回给 APISIX 的处理结果。
    - pass：请求合法
    - reject：请求被 WAF 服务器拒绝
- **X-APISIX-CHAITIN-WAF-SERVER**：调试用响应头。所使用的 WAF 服务器。

## 插件元数据

| 名称                       | 类型             | 必选项 | 默认值   | 描述                                                                                                                                            |
|--------------------------|----------------|-----|-------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| nodes                    | array(object)  | 必选  |       | 长亭 WAF 的地址列表。                                                                                                                                 |
| nodes[0].host            | string         | 必选  |       | 长亭 WAF 的地址，支持 IPV4、IPV6、Unix Socket 等配置方式。                                                                                                    |
| nodes[0].port            | string         | 可选  | 80    | 长亭 WAF 的端口。                                                                                                                                   |
| checks                   | health_checker | 可选  |       | 配置针对 WAF Server 的健康检查参数，目前只支持主动健康检查。细信息请参考 [health-check](https://github.com/apache/apisix/blob/release%2F3.4/docs/zh/latest/health-check.md) |
| config                   | object         | 否   |       | 长亭 WAF 服务的配置参数值。当路由没有配置时将使用这里所配置的参数。                                                                                                          |
| config.connect_timeout   | integer        | 否   | 1000  | connect timeout, 毫秒，默认值为 1s (1000ms)                                                                                                          |
| config.send_timeout      | integer        | 否   | 1000  | send timeout, 毫秒，默认值为 1s (1000ms)                                                                                                             |
| config.read_timeout      | integer        | 否   | 1000  | read timeout, 毫秒，默认值为 1s (1000ms)                                                                                                             |
| config.req_body_size     | integer        | 否   | 1024  | 请求体大小，单位为 KB, 默认值为 1MB (1024KB)                                                                                                               |
| config.keepalive_size    | integer        | 否   | 256   | 长亭 WAF 服务的最大并发空闲连接数，毫秒，默认值为 256                                                                                                               |
| config.keepalive_timeout | integer        | 否   | 60000 | 空闲链接超时，毫秒，默认值为 60s (60000ms)                                                                                                                  |
| config.remote_addr       | string         | 否   |       | 从 ngx.var.VARIABLE 中提取 remote_addr 的变量，默认值为 `"http_x_forwarded_for: 1"`。如果没有获取到，将从 `ngx.var.remote_addr` 获取                                   |

一个典型的示例配置如下：

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "nodes":[
     {
       "host": "unix:/path/to/safeline/resources/detector/snserver.sock",
       "port": 8000
     }
  ]
}'
```

## 属性

| 名称                       | 类型            | 必选项 | 默认值   | 描述                                                                                                                                                                                                                                                                           |
|--------------------------|---------------|-----|-------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| match                    | array[object] | 否   |       | 匹配规则列表，默认为空且规则将被无条件执行。                                                                                                                                                                                                                                                       |
| match.vars               | array[array]  | 否   |       | 由一个或多个 `{var, operator, val}` 元素组成的列表，例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于已支持的运算符，具体用法请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 `operator-list` 部分。 |
| add_header               | bool          | 否   | true  | 是否添加响应头                                                                                                                                                                                                                                                                      |
| add_debug_header         | bool          | 否   | false | 是否添加调试用响应头，`add_header` 为 `true` 时才生效                                                                                                                                                                                                                                        |
| config                   | object        | 否   |       | 长亭 WAF 服务的配置参数值。当路由没有配置时将使用元数据里所配置的参数。                                                                                                                                                                                                                                       |
| config.connect_timeout   | integer       | 否   |       | connect timeout, 毫秒                                                                                                                                                                                                                                                          |
| config.send_timeout      | integer       | 否   |       | send timeout, 毫秒                                                                                                                                                                                                                                                             |
| config.read_timeout      | integer       | 否   |       | read timeout, 毫秒                                                                                                                                                                                                                                                             |
| config.req_body_size     | integer       | 否   |       | 请求体大小，单位为 KB                                                                                                                                                                                                                                                                 |
| config.keepalive_size    | integer       | 否   |       | 长亭 WAF 服务的最大并发空闲连接数                                                                                                                                                                                                                                                          |
| config.keepalive_timeout | integer       | 否   |       | 空闲链接超时，毫秒                                                                                                                                                                                                                                                                    |
| config.remote_addr       | string        | 否   |       | 从 ngx.var.VARIABLE 中提取 remote_addr 的变量                                                                                                                                                                                                                                       |

一个典型的示例配置如下，这里使用 `httpbun.org` 作为示例后端，可以按需替换：

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
   "uri": "/*",
   "plugins": {
       "chaitin-waf": {
           "match": [
                {
                    "vars": [
                        ["http_waf","==","true"]
                    ]
                }
            ]
       }
    },
   "upstream": {
       "type": "roundrobin",
       "nodes": {
           "httpbun.org:80": 1
       }
   }
}'
```

## 测试插件

以上述的示例配置为例进行测试。

不满足匹配条件时，请求可以正常触达：

```bash
curl -H "Host: httpbun.org" http://127.0.0.1:9080/get -i

HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 408
Connection: keep-alive
X-APISIX-CHAITIN-WAF: no
Date: Wed, 19 Jul 2023 09:30:42 GMT
X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
Server: APISIX/3.3.0

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Connection": "close",
    "Host": "httpbun.org",
    "User-Agent": "curl/8.1.2",
    "X-Forwarded-For": "127.0.0.1",
    "X-Forwarded-Host": "httpbun.org",
    "X-Forwarded-Port": "9080",
    "X-Forwarded-Proto": "http",
    "X-Real-Ip": "127.0.0.1"
  },
  "method": "GET",
  "origin": "127.0.0.1, 122.231.76.178",
  "url": "http://httpbun.org/get"
}
```

面对潜在的注入请求也原样转发并遇到 404 错误：

```bash
curl -H "Host: httpbun.org" http://127.0.0.1:9080/getid=1%20AND%201=1 -i

HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8
Content-Length: 19
Connection: keep-alive
X-APISIX-CHAITIN-WAF: no
Date: Wed, 19 Jul 2023 09:30:28 GMT
X-Content-Type-Options: nosniff
X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
Server: APISIX/3.3.0

404 page not found
```

当满足匹配条件时，正常请求依然可以触达：

```bash
curl -H "Host: httpbun.org" -H "waf: true" http://127.0.0.1:9080/get -i

HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 427
Connection: keep-alive
X-APISIX-CHAITIN-WAF-TIME: 2
X-APISIX-CHAITIN-WAF-STATUS: 200
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-ACTION: pass
Date: Wed, 19 Jul 2023 09:29:58 GMT
X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
Server: APISIX/3.3.0

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Connection": "close",
    "Host": "httpbun.org",
    "User-Agent": "curl/8.1.2",
    "Waf": "true",
    "X-Forwarded-For": "127.0.0.1",
    "X-Forwarded-Host": "httpbun.org",
    "X-Forwarded-Port": "9080",
    "X-Forwarded-Proto": "http",
    "X-Real-Ip": "127.0.0.1"
  },
  "method": "GET",
  "origin": "127.0.0.1, 122.231.76.178",
  "url": "http://httpbun.org/get"
}
```

而潜在的攻击请求将会被拦截并返回 403 错误：

```bash
curl -H "Host: httpbun.org" -H "waf: true" http://127.0.0.1:9080/getid=1%20AND%201=1 -i

HTTP/1.1 403 Forbidden
Date: Wed, 19 Jul 2023 09:29:06 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-TIME: 2
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF-STATUS: 403
Server: APISIX/3.3.0
Set-Cookie: sl-session=UdywdGL+uGS7q8xMfnJlbQ==; Domain=; Path=/; Max-Age=86400

{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "51a268653f2c4189bfa3ec66afbcb26d"}
```

## 健康检查

一个典型的插件元数据配置如下，该配置包含了一个错误的服务器用以模拟异常的 WAF 服务器：

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "nodes":[
     {
        "host": "unix:/path/to/safeline/resources/detector/snserver.sock",
        "port": 8000
     }, {
        "host": "127.0.0.1",
        "port": 1551
     }
  ]
}'
```

在没有配置健康检查的情况下，一部分请求会转发到不可用的 WAF 服务器上，从而导致不可用（该输出开启了 `add_debug_header` 选项）：

```bash
curl -H "Host: httpbun.org" -H "waf: true" http://127.0.0.1:9080/get -i

HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 427
Connection: keep-alive
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-SERVER: 127.0.0.1
X-APISIX-CHAITIN-WAF-TIME: 1
X-APISIX-CHAITIN-WAF-ACTION: pass
X-APISIX-CHAITIN-WAF-ERROR: failed to connect to t1k server 127.0.0.1:1551: connection refused
Date: Wed, 19 Jul 2023 09:41:20 GMT
X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
Server: APISIX/3.3.0

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Connection": "close",
    "Host": "httpbun.org",
    "User-Agent": "curl/8.1.2",
    "Waf": "true",
    "X-Forwarded-For": "127.0.0.1",
    "X-Forwarded-Host": "httpbun.org",
    "X-Forwarded-Port": "9080",
    "X-Forwarded-Proto": "http",
    "X-Real-Ip": "127.0.0.1"
  },
  "method": "GET",
  "origin": "127.0.0.1, 122.231.76.178",
  "url": "http://httpbun.org/get"
}
```

添加了健康检查的示例配置如下，此时健康检查将会过滤掉不可用的 WAF 服务器：

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "nodes":[
        {
            "host": "unix:/path/to/safeline/resources/detector/snserver.sock",
            "port": 8000
        },
        {
            "host": "127.0.0.1",
            "port": 1551
        }
    ],

    "checks": {
        "active": {
            "type": "tcp",
            "host": "localhost",
            "timeout": 5,
            "http_path": "/",
            "healthy": {
                "interval": 2,
                "successes": 1
            },
            "unhealthy": {
                "interval": 1,
                "http_failures": 2
            },
            "req_headers": ["User-Agent: curl/7.29.0"]
        }
    }
}'
```

## 禁用插件

需要禁用 `tencent-waf` 插件时，在插件配置中删除相应的插件配置即可：

```bash
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
   "uri": "/*",
   "upstream": {
       "type": "roundrobin",
       "nodes": {
           "httpbun.org:80": 1
       }
   }
}'
```
