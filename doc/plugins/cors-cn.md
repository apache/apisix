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

# [English](cors.md)

# 目录

- [**简介**](#简介)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 简介

`cors` 插件可以让你轻易地为服务端启用 [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) 的返回头。

## 属性

- `allow_origins`: `可选`，允许跨域访问的 Origin，格式如：`scheme`://`host`:`port`，比如: https://somehost.com:8081。多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示所有 Origin 均允许通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Origin 都通过，但请注意这样存在安全隐患。默认值为 `*`。
- `allow_methods`: `可选`，允许跨域访问的 Method，比如: `GET`，`POST`等。多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示所有 Origin 均允许通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Method 都通过，但请注意这样存在安全隐患。默认值为 `*`。
- `allow_headers`: `可选`，允许跨域访问时请求方携带哪些非 `CORS规范` 以外的 Header， 多个值使用 `,` 分割。默认值为 `*`。
- `expose_headers`: `可选`，允许跨域访问时响应方携带哪些非 `CORS规范` 以外的 Header， 多个值使用 `,` 分割。默认值为 `*`。
- `max_age`: `可选`，浏览器缓存 CORS 结果的最大时间，单位为秒，在这个时间范围内浏览器会复用上一次的检查结果，`-1` 表示不缓存。请注意各个浏览器允许的的最大时间不用，详情请参考 [MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives). 默认值为 `5`。
- `allow_credential`: 是否允许跨域访问的请求方携带凭据(如 Cookie 等)，默认值为: `false`。

## 如何启用

创建 `Route` 或 `Service` 对象，并配置 `cors` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "cors": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 测试插件

请求下接口，发现接口已经返回了`CORS`相关的header，代表插件生效
```shell
curl http://127.0.0.1:9080/hello -v
...
< Server: APISIX web server
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Methods: *
< Access-Control-Allow-Headers: *
< Access-Control-Expose-Headers: *
< Access-Control-Max-Age: 5
...
```

## 禁用插件

从配置中移除`cors`插件即可。
```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
