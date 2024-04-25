---
title: cors
keywords:
  - Apache APISIX
  - API 网关
  - CORS
description: 本文介绍了 Apache APISIX cors 插件的基本信息及使用方法。
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

`cors` 插件可以让你轻松地为服务端启用 [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)（Cross-Origin Resource Sharing，跨域资源共享）的返回头。

## 属性

| 名称             | 类型    | 必选项 | 默认值 | 描述                                                         |
| ---------------- | ------- | ------ | ------ | ------------------------------------------------------------ |
| allow_origins    | string  | 否   | "*"    | 允许跨域访问的 Origin，格式为 `scheme://host:port`，示例如 `https://somedomain.com:8081`。如果你有多个 Origin，请使用 `,` 分隔。当 `allow_credential` 为 `false` 时，可以使用 `*` 来表示允许所有 Origin 通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Origin 均通过，但请注意这样存在安全隐患。 |
| allow_methods    | string  | 否   | "*"    | 允许跨域访问的 Method，比如：`GET`，`POST` 等。如果你有多个 Method，请使用 `,` 分割。当 `allow_credential` 为 `false` 时，可以使用 `*` 来表示允许所有 Method 通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Method 都通过，但请注意这样存在安全隐患。 |
| allow_headers    | string  | 否   | "*"    | 允许跨域访问时请求方携带哪些非 `CORS 规范` 以外的 Header。如果你有多个 Header，请使用 `,` 分割。当 `allow_credential` 为 `false` 时，可以使用 `*` 来表示允许所有 Header 通过。你也可以在启用了 `allow_credential` 后使用 `**` 强制允许所有 Header 都通过，但请注意这样存在安全隐患。 |
| expose_headers   | string  | 否   |        | 允许跨域访问时响应方携带哪些非 CORS 规范 以外的 Header。如果你有多个 Header，请使用 , 分割。当 allow_credential 为 false 时，可以使用 * 来表示允许任意 Header。如果不设置，插件不会修改 `Access-Control-Expose-Headers` 头，详情请参考 [Access-Control-Expose-Headers - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Expose-Headers)。 |
| max_age          | integer | 否   | 5      | 浏览器缓存 CORS 结果的最大时间，单位为秒。在这个时间范围内，浏览器会复用上一次的检查结果，`-1` 表示不缓存。请注意各个浏览器允许的最大时间不同，详情请参考 [Access-Control-Max-Age - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#directives)。 |
| allow_credential | boolean | 否   | false  | 是否允许跨域访问的请求方携带凭据（如 Cookie 等）。根据 CORS 规范，如果设置该选项为 `true`，那么将不能在其他属性中使用 `*`。 |
| allow_origins_by_regex | array | 否   | nil  | 使用正则表达式数组来匹配允许跨域访问的 Origin，如 `[".*\.test.com$"]` 可以匹配任何 `test.com` 的子域名。如果 `allow_origins_by_regex` 属性已经指定，则会忽略 `allow_origins` 属性。 |
| allow_origins_by_metadata | array | 否    | nil   | 通过引用插件元数据的 `allow_origins` 配置允许跨域访问的 Origin。比如当插件元数据为 `"allow_origins": {"EXAMPLE": "https://example.com"}` 时，配置 `["EXAMPLE"]` 将允许 Origin `https://example.com` 的访问。  |

:::info IMPORTANT

1. `allow_credential` 是一个很敏感的选项，请谨慎开启。开启之后，其他参数默认的 `*` 将失效，你必须显式指定它们的值。
2. 在使用 `**` 时，需要清楚该参数引入的一些安全隐患，比如 CSRF，并确保这样的安全等级符合自己预期。

:::

## 元数据

| 名称           | 类型    | 必选项  | 描述                       |
| -----------   | ------  | ------ | ------------------ |
| allow_origins | object  | 否    | 定义允许跨域访问的 Origin；它的键为 `allow_origins_by_metadata` 使用的引用键，值则为允许跨域访问的 Origin，其语义与属性中的 `allow_origins` 相同。 |

## 启用插件

你可以在路由或服务上启用 `cors` 插件。

你可以通过如下命令在指定路由上启用 `cors` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl http://127.0.0.1:9080/hello -v
```

如果返回结果中出现 CORS 相关的 header，则代表插件生效：

```shell
...
< Server: APISIX web server
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Methods: *
< Access-Control-Allow-Headers: *
< Access-Control-Max-Age: 5
...
```

## 删除插件

当你需要禁用 `cors` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
