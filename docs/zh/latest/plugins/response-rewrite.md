---
title: response-rewrite
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Response Rewrite
  - response-rewrite
description: response-rewrite 插件提供了重写 APISIX 及其上游服务返回给客户端的响应的选项。使用该插件，您可以修改 HTTP 状态代码、请求标头、响应正文等。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/response-rewrite" />
</head>

## 描述

`response-rewrite` 插件提供了重写 APISIX 及其上游服务返回给客户端的响应的选项。使用此插件，您可以修改 HTTP 状态代码、请求标头、响应正文等。

例如，您可以使用此插件来：

- 通过设置 `Access-Control-Allow-*` 标头来支持 [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)。
- 通过设置 HTTP 状态代码和 `Location` 标头来指示重定向。

:::tip

如果你仅需要重定向功能，建议使用 [redirect](redirect.md) 插件。

:::

## 属性

| 名称            | 类型    | 必选项 | 默认值 | 有效值          | 描述                                                                                                                                                                                                                      |
|-----------------|---------|--------|--------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| status_code     | integer | 否     |        | [200, 598]      | 修改上游返回状态码，默认保留原始响应代码。                                                                                                                                                                                |
| body            | string  | 否     |        |                 | 修改上游返回的 `body` 内容，如果设置了新内容，header 里面的 `Content-Length` 字段也会被去掉。                                                                                                                               |
| body_base64     | boolean | 否     | false  |                 | 如果为 true，则在发送到客户端之前解码`body` 中配置的响应主体，这对于图像和 protobuf 解码很有用。请注意，此配置不能用于解码上游响应。                                                                                                                                 |
| headers | object | 否 | | | 按照 `add`、`remove` 和 `set` 的顺序执行的操作。 |
| headers.add | array[string] | 否 | | | 要附加到请求的标头。如果请求中已经存在标头，则会附加标头值。标头值可以设置为常量，也可以设置为一个或多个 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。 |
| headers.set | object | 否 | | |要设置到请求的标头。如果请求中已经存在标头，则会覆盖标头值。标头值可以设置为常量，也可以设置为一个或多个[Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。 |
| headers.remove | array[string] | 否 | | | 要从请求中删除的标头。 |
| vars | array[array] | 否 | | | 以 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的形式包含一个或多个匹配条件的数组。 |
| filters | array[object] | 否 | | | 通过将一个指定字符串替换为另一个指定字符串来修改响应主体的过滤器列表。不应与 `body` 一起配置。 |
| filters.regex | string | True | | | 用于匹配响应主体的 RegEx 模式。 |
| filters.scope | string | 否 | "once" | ["once","global"] | 替换范围。`once` 替换第一个匹配的实例，`global` 全局替换。 |
| filters.replace | string | True | | | 要替换的内容。 |
| filters.options | string | 否 | "jo" | | 用于控制如何执行匹配操作的 RegEx 选项。请参阅[Lua NGINX 模块](https://github.com/openresty/lua-nginx-module#ngxrematch)以了解可用选项。|

## 示例

以下示例演示了如何在不同场景中在路由上配置 `response-rewrite`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 重写标头和正文

以下示例演示了如何添加响应正文和标头，仅适用于具有 `200` HTTP 状态代码的响应。

创建一个带有 `response-rewrite` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {
      "response-rewrite": {
        "body": "{\"code\":\"ok\",\"message\":\"new json body\"}",
        "headers": {
          "set": {
            "X-Server-id": 3,
            "X-Server-status": "on",
            "X-Server-balancer-addr": "$balancer_ip:$balancer_port"
          }
        },
        "vars": [
          [ "status","==",200 ]
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

发送请求以验证：

```shell
curl -i "http://127.0.0.1:9080/headers"
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```text
...
X-Server-id: 3
X-Server-status: on
X-Server-balancer-addr: 50.237.103.220:80

{"code":"ok","message":"new json body"}
```

### 使用 RegEx 过滤器重写标头

以下示例演示如何使用 RegEx 过滤器匹配替换响应中的 `X-Amzn-Trace-Id`。

创建一个带有 `response-rewrite` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins":{
      "response-rewrite":{
        "filters":[
          {
            "regex":"X-Amzn-Trace-Id",
            "scope":"global",
            "replace":"X-Amzn-Trace-Id-Replace"
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

发送请求以验证：

```shell
curl -i "http://127.0.0.1:9080/headers"
```

您应该会看到类似以下内容的响应：

```text
{
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id-Replace": "Root=1-6500095d-1041b05e2ba9c6b37232dbc7",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### 从 Base64 解码正文

以下示例演示如何从 Base64 格式解码正文。

创建一个带有 `response-rewrite` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/get",
    "plugins":{
      "response-rewrite": {
        "body": "SGVsbG8gV29ybGQ=",
        "body_base64": true
        }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

发送请求以验证：

```shell
curl "http://127.0.0.1:9080/get"
```

您应该看到以下响应：

```text
Hello World
```

### 重写响应及其与执行阶段的联系

以下示例通过使用 `key-auth` 插件配置插件，演示了 `response-rewrite` 插件与 [执行阶段](/apisix/key-concepts/plugins#plugins-execution-lifecycle) 之间的联系，并查看在未经身份验证的请求的情况下，响应仍如何重写为 `200 OK`。

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

创建一个带有 `key-auth` 的路由，并配置 `response-rewrite` 来重写响应状态码和主体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
   -H "X-API-KEY: ${admin_key}" \
   -d '{
    "id": "response-rewrite-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "response-rewrite": {
        "status_code": 200,
        "body": "{\"code\": 200, \"msg\": \"success\"}"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

使用有效密钥向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jack-key'
```

您应该收到以下 `HTTP/1.1 200 OK` 响应：

```text
{"code": 200, "msg": "success"}
```

向路由发送一个没有任何键的请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您仍应收到相同的 `HTTP/1.1 200 OK` 响应，而不是来自 `key-auth` 插件的 `HTTP/1.1 401 Unauthorized`。这表明 `response-rewrite` 插件仍在重写响应。

这是因为 `response-rewrite` 插件的 **header_filter** 和 **body_filter** 阶段逻辑将在 [`ngx.exit`](https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxexit) 之后在其他插件的 **access** 或 **rewrite** 阶段继续运行。

下表总结了 `ngx.exit` 对执行阶段的影响。

| 阶段         | rewrite  | access   | header_filter | body_filter |
|---------------|----------|----------|---------------|-------------|
| **rewrite**       | ngx.exit |          |               |           |
| **access**        | ×        | ngx.exit |               |           |
| **header_filter** | ✓        | ✓        | ngx.exit      |           |
| **body_filter**   | ✓        | ✓        | ×             | ngx.exit  |

例如，如果 `ngx.exit` 发生在 **rewrite** 阶段，它将中断 **access** 阶段的执行，但不会干扰 **header_filter** 和 **body_filter** 阶段。
