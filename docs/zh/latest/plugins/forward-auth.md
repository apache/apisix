---
title: forward-auth
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

`forward-auth` 插件使用的是经典外部认证。在认证失败的时候，我们可以实现自定义错误或者重定向到认证页面。

Forward Auth 巧妙地将认证和授权逻辑移到了一个专门的外部服务中，网关将用户的请求转发给认证服务并阻塞原始请求，并在认证服务以非 2xx 状态响应时替换结果。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| -- | -- | -- | -- | -- | -- |
| host | string | 必须 |  |  | 设置 `authorization` 服务的地址 (eg. https://localhost:9188) |
| ssl_verify | boolean | 可选 | true |   | 是否验证证书 |
| request_headers | array[string] | 可选 |  |  | 设置需要由 `client` 转发到 `authorization` 服务的请求头。未设置时，只有 Apache APISIX 的(X-Forwarded-XXX)会被转发到 `authorization` 服务。 |
| upstream_headers | array[string] | 可选 |  |  | 认证通过时，设置 `authorization` 服务转发至 `upstream` 的请求头。如果不设置则不转发任何请求头。
| client_headers | array[string] | 可选 |  |  | 认证失败时，由 `authorization` 服务向 `client` 发送的响应头。如果不设置则不转发任何响应头。 |
| timeout | integer | 可选 | 3000ms | [1, 60000]ms | `authorization` 服务请求超时时间 |
| keepalive | boolean | 可选 | true |  | HTTP 长连接 |
| keepalive_timeout | integer | 可选 | 60000ms | [1000, ...]ms | 长连接超时时间 |
| keepalive_pool | integer | 可选 | 5 | [1, ...]ms | 长连接池大小 |

## 数据定义

request_headers 属性中转发到 `authorization` 服务中的 Apache APISIX 内容清单
| Scheme | HTTP Method | Host | URI | Source IP |
| -- | -- | -- | -- | -- |
| X-Forwarded-Proto | X-Forwarded-Method | X-Forwarded-Host | X-Forwarded-Uri | X-Forwarded-For |

## 示例

首先, 你需要设置一个认证服务。这里使用的是 Apache APISIX 无服务器插件模拟的示例。

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/auth' \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
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

下一步, 我们创建一个测试路由。

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/1' \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
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

我们可以进行下面三个测试：

1. **request_headers** 从 `client` 转发请求头到 `authorization` 服务

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

2. **upstream_headers** 转发 `authorization` 服务响应头到 `upstream`

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

3. **client_headers** 当授权失败时转发 `authorization` 服务响应头到 `client`

```shell
curl -i http://127.0.0.1:9080/headers
```

```
HTTP/1.1 403 Forbidden
Location: http://example.com/auth
```

最后，你可以通过在路由中移除的方式禁用 `forward-auth` 插件。
