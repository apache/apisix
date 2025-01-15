---
title: forward-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Forward Authentication
  - forward-auth
description: 本文介绍了关于 Apache APISIX `forward-auth` 插件的基本信息及使用方法。
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

`forward-auth` 插件使用的是经典外部认证。当身份认证失败时，可以实现自定义错误或者重定向到认证页面的场景。

`forward-auth` 插件巧妙地将身份认证和授权逻辑移到了一个专门的外部服务中，APISIX 将用户的请求转发给认证服务并阻塞原始请求，然后在认证服务下以非 2xx 状态响应时进行结果替换。

## 属性

| 名称              | 类型           | 必选项 |  默认值 | 有效值         | 描述                                                                                                               |
| ----------------- | ------------- | ------| ------- | -------------- | -------------------------------------------------------------------------------------------------------------------- |
| uri               | string        | 是    |         |                | 设置 `authorization` 服务的地址 (例如：https://localhost:9188)。                                                      |
| ssl_verify        | boolean       | 否    | true    | [true, false]  | 当设置为 `true` 时，验证 SSL 证书。                                                                                  |
| request_method    | string        | 否    | GET     | ["GET","POST"] | 客户端向 `authorization` 服务发送请求的方法。当设置为 POST 时，会将 `request body` 转发至 `authorization` 服务。         |
| request_headers   | array[string] | 否    |         |                | 设置需要由客户端转发到 `authorization` 服务的请求头。如果没有设置，则只发送 APISIX 提供的 headers (例如：X-Forwarded-XXX)。 |
| upstream_headers  | array[string] | 否    |         |                | 认证通过时，设置 `authorization` 服务转发至 `upstream` 的请求头。如果不设置则不转发任何请求头。                             |
| client_headers    | array[string] | 否    |         |                | 认证失败时，由 `authorization` 服务向 `client` 发送的响应头。如果不设置则不转发任何响应头。                                |
| timeout           | integer       | 否    | 3000ms  | [1, 60000]ms   | `authorization` 服务请求超时时间。                                                                                     |
| keepalive         | boolean       | 否    | true    | [true, false]  | HTTP 长连接。                                                                                                         |
| keepalive_timeout | integer       | 否    | 60000ms | [1000, ...]ms  | 长连接超时时间。                                                                                                      |
| keepalive_pool    | integer       | 否    | 5       | [1, ...]ms     | 长连接池大小。                                                                                                        |
| allow_degradation | boolean       | 否    | false   |                | 当设置为 `true` 时，允许在身份验证服务器不可用时跳过身份验证。 |
| status_on_error   | integer       | 否    | 403     | [200,...,599]   | 设置授权服务出现网络错误时返回给客户端的 HTTP 状态。默认状态为“403”。 |

## 数据定义

APISIX 将生成并发送如下所示的请求头到认证服务：

| Scheme            | HTTP Method        | Host              | URI             | Source IP       |
| ----------------- | ------------------ | ----------------- | --------------- | --------------- |
| X-Forwarded-Proto | X-Forwarded-Method | X-Forwarded-Host  | X-Forwarded-Uri | X-Forwarded-For |

## 使用示例

首先，你需要设置一个外部认证服务。以下示例使用的是 Apache APISIX 无服务器插件模拟服务：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/auth' \
    -H "X-API-KEY: $admin_key" \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/auth",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": [
                "return function (conf, ctx)
                    local core = require(\"apisix.core\");
                    local authorization = core.request.header(ctx, \"Authorization\");
                    if authorization == \"123\" then
                        core.response.exit(200);
                    elseif authorization == \"321\" then
                        core.response.set_header(\"X-User-ID\", \"i-am-user\");
                        core.response.exit(200);
                    else core.response.set_header(\"Location\", \"http://example.com/auth\");
                        core.response.exit(403);
                    end
                end"
            ]
        }
    }
}'
```

现在你可以在指定 Route 上启用 `forward-auth` 插件：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/1' \
    -H "X-API-KEY: $admin_key" \
    -d '{
    "uri": "/headers",
    "plugins": {
        "forward-auth": {
            "uri": "http://127.0.0.1:9080/auth",
            "request_headers": ["Authorization"],
            "upstream_headers": ["X-User-ID"],
            "client_headers": ["Location"]
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    }
}'
```

完成上述配置后，可通过以下三种方式进行测试：

- 在请求头中发送认证的详细信息：

```shell
curl http://127.0.0.1:9080/headers -H 'Authorization: 123'
```

```
{
    "headers": {
        "Authorization": "123",
        "Next": "More-headers"
    }
}
```

- 转发认证服务响应头到 Upstream。

```shell
curl http://127.0.0.1:9080/headers -H 'Authorization: 321'
```

```
{
    "headers": {
        "Authorization": "321",
        "X-User-ID": "i-am-user",
        "Next": "More-headers"
    }
}
```

- 当授权失败时，认证服务可以向用户发送自定义响应：

```shell
curl -i http://127.0.0.1:9080/headers
```

```shell
HTTP/1.1 403 Forbidden
Location: http://example.com/auth
```

## 删除插件

当你需要禁用 `forward-auth` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```
