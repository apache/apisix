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

在启用 `chaitin-waf` 插件后，流量将被转发给长亭 WAF 服务，用以检测和防止各种 Web 应用程序攻击，以保护应用程序和用户数据的安全。

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

| 名称                       | 类型            | 必选项 | 默认值   | 描述                                         |
|--------------------------|---------------|-----|-------|--------------------------------------------|
| nodes                    | array(object) | 必选  |       | 长亭 WAF 的地址列表。                              |
| nodes[0].host            | string        | 必选  |       | 长亭 WAF 的地址，支持 IPV4、IPV6、Unix Socket 等配置方式。 |
| nodes[0].port            | string        | 可选  | 80    | 长亭 WAF 的端口。                                |
| config                   | object        | 否   |       | 长亭 WAF 服务的配置参数值。当路由没有配置时将使用这里所配置的参数。       |
| config.connect_timeout   | integer       | 否   | 1000  | connect timeout, 毫秒                        |
| config.send_timeout      | integer       | 否   | 1000  | send timeout, 毫秒                           |
| config.read_timeout      | integer       | 否   | 1000  | read timeout, 毫秒                           |
| config.req_body_size     | integer       | 否   | 1024  | 请求体大小，单位为 KB                               |
| config.keepalive_size    | integer       | 否   | 256   | 长亭 WAF 服务的最大并发空闲连接数                        |
| config.keepalive_timeout | integer       | 否   | 60000 | 空闲链接超时，毫秒                                  |

一个典型的示例配置如下：

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H "X-API-KEY: $admin_key" -X PUT -d '
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
| append_waf_resp_header   | bool          | 否   | true  | 是否添加响应头                                                                                                                                                                                                                                                                      |
| append_waf_debug_header  | bool          | 否   | false | 是否添加调试用响应头，`add_header` 为 `true` 时才生效                                                                                                                                                                                                                                        |
| config                   | object        | 否   |       | 长亭 WAF 服务的配置参数值。当路由没有配置时将使用元数据里所配置的参数。                                                                                                                                                                                                                                       |
| config.connect_timeout   | integer       | 否   |       | connect timeout, 毫秒                                                                                                                                                                                                                                                          |
| config.send_timeout      | integer       | 否   |       | send timeout, 毫秒                                                                                                                                                                                                                                                             |
| config.read_timeout      | integer       | 否   |       | read timeout, 毫秒                                                                                                                                                                                                                                                             |
| config.req_body_size     | integer       | 否   |       | 请求体大小，单位为 KB                                                                                                                                                                                                                                                                 |
| config.keepalive_size    | integer       | 否   |       | 长亭 WAF 服务的最大并发空闲连接数                                                                                                                                                                                                                                                          |
| config.keepalive_timeout | integer       | 否   |       | 空闲链接超时，毫秒                                                                                                                                                                                                                                                                    |

一个典型的示例配置如下，这里使用 `httpbun.org` 作为示例后端，可以按需替换：

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

当满足匹配条件时，正常请求依然可以触达上游：

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

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```bash
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
