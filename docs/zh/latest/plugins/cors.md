---
title: cors
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

## 简介

启用该插件后，网关将针对路由根据预设参数设置 CORS 规则，以便消费者在浏览器中发起请求。

## 术语

- Origin：请求首部字段 Origin 指示了请求来自于哪个站点。该字段仅指示服务器名称，并不包含任何路径信息。该首部用于 CORS 请求或者 POST 请求。除了不包含路径信息，该字段与 Referer 首部字段相似。

## 参数

|         参数名         |    类型    | 必选  | 默认值 |                                                                                                                                                                                                        描述                                                                                                                                                                                                         |
| :--------------------: | :--------: | :---: | :----: | :-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: |
|     allow_origins      |   字符串   |  否   |   *    |                                                         `Access-Control-Allow-Origin` 请求头表示允许跨域的 Origin 白名单，格式：`协议://主机名:端口号`。当有多个值时，使用 `,` 分隔。当 `allow_credential = false` 时，可以使用 `*` 以允许任意 Origin；当 `allow_credential = true` 时，可以使用 `**` 强制允许任意 Origin，但这会产生安全问题，不推荐使用。                                                         |
|     allow_methods      |   字符串   |  否   |   *    | `Access-Control-Allow-Methods` 请求头表示允许跨域的 HTTP 方法白名单，例如：`GET/POST/PUT` 等                                                                                                            。当有多个值时，使用 `,` 分隔。当 `allow_credential = false` 时，可以使用 `*` 以允许任意 HTTP 方法；当 `allow_credential = true` 时，可以使用 `**` 强制允许任意 HTTP 方法，但这会产生安全问题，不推荐使用。 |
|     allow_headers      |   字符串   |  否   |   *    |                                             `Access-Control-Allow-Headers` 请求头表示当访问跨域资源时，允许消费者携带哪些非 CORS 规范以外的 HTTP 请求头。当有多个值时，使用 `,` 分隔。当 `allow_credential = false` 时，可以使用 `*` 以允许任意 HTTP 请求头；当 `allow_credential = true` 时，可以使用 `**` 强制允许任意 HTTP 请求头，但这会产生安全问题，不推荐使用。                                              |
|     expose_headers     |   字符串   |  否   |   *    |                                                                                                                                               `Access-Control-Expose-Headers` 响应头表示当访问跨域资源时，允许响应方返回哪些 HTTP 请求头。有多个值时，使用 `,` 分隔。                                                                                                                                               |
|        max_age         |   整数型   |  否   |   5    |               `Access-Controll-Max-Age` 响应头表示 `preflight request` 预检请求的返回结果（即 Access-Control-Allow-Methods 与 Access-Control-Allow-Headers 提供的信息）可以被缓存多久。单位为秒，在该时间范围内浏览器将复用上一次的检查结果，`-1` 表示不缓存。注意：不同浏览器允许的最大时间不同，具体请见 [MDN](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers/Access-Control-Max-Age)。                |
|    allow_credential    |   布尔值   |  否   | false  |                                                                                                                                 `Access-Control-Allow-Credentials` 响应头表示是否可以将对请求的响应暴露给前端 JS，只有 `allow_credential = true` 才可以，此时其它选项不可以为 `*`。                                                                                                                                 |
| allow_origins_by_regex | 字符串数组 |  否   |  nil   |                                                                                                                                                        使用正则表达式数组以匹配允许跨域访问的 Origin，如 `["*.test.com"]` 可以匹配 `test.com` 的子域名 `*`。                                                                                                                                                        |

## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下示例使用了 `cors` 插件的默认配置，即允许任意 Origin 访问。

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "cors": {}
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```

接着，访问路由进行测试：

```bash
# 场景1：在未启用 CORS 插件时，访问资源：

## Request
$ curl -i http://127.0.0.1:9080/get -v

## Response
< Access-Control-Allow-Origin: *
Access-Control-Allow-Origin: *
< Access-Control-Allow-Credentials: true
Access-Control-Allow-Credentials: true

# 场景2：启用 CORS 插件后，再发出请求：

## Request
$ curl -i http://127.0.0.1:9080/get -v

## Response
...
< Access-Control-Allow-Origin: *
Access-Control-Allow-Origin: *
< Access-Control-Allow-Credentials: true
Access-Control-Allow-Credentials: true
< Access-Control-Allow-Methods: *
Access-Control-Allow-Methods: *
< Access-Control-Max-Age: 5
Access-Control-Max-Age: 5
< Access-Control-Expose-Headers: *
Access-Control-Expose-Headers: *
< Access-Control-Allow-Headers: *
Access-Control-Allow-Headers: *
```

## 使用 AdminAPI 禁用插件

如果希望禁用插件，只需更新路由配置，从 plugins 字段移除该插件即可：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```
