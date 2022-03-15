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

## 描述

`cors` 插件可以让你为服务端启用 [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) 的返回头。

## 属性

| 名称             | 类型    | 可选项 | 默认值 | 有效值 | 描述                                                         |
| ---------------- | ------- | ------ | ------ | ------ | ------------------------------------------------------------ |
| allow_origins    | string  | 可选   | "*"    |        | 允许跨域访问的 Origin，格式如：`scheme`://`host`:`port`，比如: https://somehost.com:8081 。多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示所有 Origin 均允许通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Origin 都通过，但请注意这样存在安全隐患。 |
| allow_methods    | string  | 可选   | "*"    |        | 允许跨域访问的 Method，比如: `GET`，`POST`等。多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示所有 Origin 均允许通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Method 都通过，但请注意这样存在安全隐患。 |
| allow_headers    | string  | 可选   | "*"    |        | 允许跨域访问时请求方携带哪些非 `CORS 规范` 以外的 Header， 多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示所有 Header 均允许通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Header 都通过，但请注意这样存在安全隐患。 |
| expose_headers   | string  | 可选   | "*"    |        | 允许跨域访问时响应方携带哪些非 `CORS 规范` 以外的 Header， 多个值使用 `,` 分割，`allow_credential` 为 `false` 时可以使用 `*` 来表示允许任意 Header 。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许任意 Header，但请注意这样存在安全隐患。 |
| max_age          | integer | 可选   | 5      |        | 浏览器缓存 CORS 结果的最大时间，单位为秒，在这个时间范围内浏览器会复用上一次的检查结果，`-1` 表示不缓存。请注意各个浏览器允许的最大时间不同，详情请参考 [MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives)。 |
| allow_credential | boolean | 可选   | false  |        | 是否允许跨域访问的请求方携带凭据（如 Cookie 等）。根据 CORS 规范，如果设置该选项为 `true`，那么将不能在其他选项中使用 `*`。 |
| allow_origins_by_regex | array | 可选   | nil  |        | 使用正则表达式数组来匹配允许跨域访问的 Origin，如[".*\.test.com"] 可以匹配任何test.com的子域名`*`。 |
| allow_origins_by_metadata | array | 可选    | nil   |       | 通过引用插件元数据的 `allow_origins` 配置允许跨域访问的 Origin。比如当元数据为 `"allow_origins": {"EXAMPLE": "https://example.com"}` 时，配置 `["EXAMPLE"]` 将允许 Origin `https://example.com` 的访问  |

> **提示**
>
> 请注意 `allow_credential` 是一个很敏感的选项，谨慎选择开启。开启之后，其他参数默认的 `*` 将失效，你必须显式指定它们的值。
> 使用 `**` 时要充分理解它引入了一些安全隐患，比如 CSRF，所以确保这样的安全等级符合自己预期再使用。

## 元数据

| 名称           | 类型    | 必选项  | 默认值 | 有效值 | 描述                       |
| -----------   | ------  | ------ | ----- | ----- |  ------------------        |
| allow_origins | object  | 可选    |       |       | 定义允许跨域访问的 Origin；它的键为 `allow_origins_by_metadata` 使用的引用键， 值则为允许跨域访问的 Origin，其语义与 `allow_origins` 相同 |

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

请求下接口，发现接口已经返回了 `CORS` 相关的header，代表插件生效

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

当你想去掉 `cors` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 `cors` 插件了。其他插件的开启和移除也是同样的方法。
