---
title: response-rewrite
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Response Rewrite
  - response-rewrite
description: 本文介绍了关于 Apache APISIX `response-rewrite` 插件的基本信息及使用方法。
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

`response-rewrite` 插件支持修改上游服务或 APISIX 返回的 Body 和 Header 信息。

该插件可以应用在以下场景中：

- 通过设置 `Access-Control-Allow-*` 字段实现 CORS（跨域资源共享）的功能。
- 通过设置标头中的 `status_code` 和 `Location` 字段实现重定向。

:::tip

如果你仅需要重定向功能，建议使用 [redirect](redirect.md) 插件。

:::

## 属性

| 名称            | 类型    | 必选项 | 默认值 | 有效值          | 描述                                                                                                                                                                                                                      |
|-----------------|---------|--------|--------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| status_code     | integer | 否     |        | [200, 598]      | 修改上游返回状态码，默认保留原始响应代码。                                                                                                                                                                                |
| body            | string  | 否     |        |                 | 修改上游返回的 `body` 内容，如果设置了新内容，header 里面的 content-length 字段也会被去掉。                                                                                                                               |
| body_base64     | boolean | 否     | false  |                 | 当设置时，在写给客户端之前，在`body`中传递的主体将被解码，这在一些图像和 Protobuffer 场景中使用。注意，这个字段只允许对插件配置中传递的主体进行解码，并不对上游响应进行解码。                                                                                                                                 |
| headers         | object  | 否     |        |                 |                                                                                                                                                                                                                           |
| headers.add     | array   | 否     |        |                 | 添加新的响应头。格式为 `["name: value", ...]`。这个值能够以 `$var` 的格式包含 NGINX 变量，比如 `$remote_addr $balancer_ip`。                                                                                              |
| headers.set     | object  | 否     |        |                 | 改写响应头。格式为 `{"name": "value", ...}`。这个值能够以 `$var` 的格式包含 NGINX 变量，比如 `$remote_addr $balancer_ip`。                                                                                                |
| headers.remove  | array   | 否     |        |                 | 移除响应头。格式为 `["name", ...]`。                                                                                                                                                                                      |
| vars            | array[] | 否     |        |                 | `vars` 是一个表达式列表，只有满足条件的请求和响应才会修改 body 和 header 信息，来自 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。如果 `vars` 字段为空，那么所有的重写动作都会被无条件的执行。 |
| filters         | array[] | 否     |        |                 | 一组过滤器，采用指定字符串表达式修改响应体。                                                                                                                                                                              |
| filters.regex   | string  | 是     |        |                 | 用于匹配响应体正则表达式。                                                                                                                                                                                                |
| filters.scope   | string  | 否     | "once" | "once","global" | 替换范围，"once" 表达式 `filters.regex` 仅替换首次匹配上响应体的内容，"global" 则进行全局替换。                                                                                                                           |
| filters.replace | string  | 是     |        |                 | 替换后的内容。                                                                                                                                                                                                            |
| filters.options | string  | 否     | "jo"   |                 | 正则匹配有效参数，可选项见 [ngx.re.match](https://github.com/openresty/lua-nginx-module#ngxrematch)。                                                                                                                     |

:::note

`body` 和 `filters` 属性只能配置其中一个。

:::

## 启用插件

你可以通过如下命令在指定路由上启用 `response-rewrite` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
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
            "vars":[
                [ "status","==",200 ]
            ]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

在上述命令中，通过配置 `vars` 参数可以让该插件仅在具有 200 状态码的响应上运行插件。

除了 `set` 操作，你也可以像这样增加或移除响应头：

```json
"headers": {
    "add": [
        "X-Server-balancer-addr: $balancer_ip:$balancer_port"
    ],
    "remove": [
        "X-TO-BE-REMOVED"
    ]
}
```

这些操作的执行顺序为 ["add", "set", "remove"]。

我们不再对直接在 `headers` 下面设置响应头的方式提供支持。
如果你的配置是把响应头设置到 `headers` 的下一层，你需要将这些配置移到 `headers.set`。

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl -X GET -i http://127.0.0.1:9080/test/index.html
```

无论来自上游的响应是什么，返回结果都是相同的：

```shell
HTTP/1.1 200 OK
Date: Sat, 16 Nov 2019 09:15:12 GMT
Transfer-Encoding: chunked
Connection: keep-alive
X-Server-id: 3
X-Server-status: on
X-Server-balancer-addr: 127.0.0.1:80

{"code":"ok","message":"new json body"}
```

:::info IMPORTANT

[ngx.exit](https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxexit) 将会中断当前请求的执行并将其状态码返回给 NGINX。

如果你在 `access` 阶段执行了 `ngx.exit`，该操作只是中断了请求处理阶段，响应阶段仍然会处理。如果你配置了 `response-rewrite` 插件，它会强制覆盖你的响应信息（如响应代码）。

| Phase         | rewrite  | access   | header_filter | body_filter |
|---------------|----------|----------|---------------|-------------|
| rewrite       | ngx.exit | √        | √             | √           |
| access        | ×        | ngx.exit | √             | √           |
| header_filter | √        | √        | ngx.exit      | √           |
| body_filter   | √        | √        | ×             | ngx.exit    |

:::

使用 `filters` 正则匹配将返回 body 的 X-Amzn-Trace-Id 替换为 X-Amzn-Trace-Id-Replace。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins":{
    "response-rewrite":{
      "headers":{
        "set": {
            "X-Server-id":3,
            "X-Server-status":"on",
            "X-Server-balancer-addr":"$balancer_ip:$balancer_port"
        }
      },
      "filters":[
        {
          "regex":"X-Amzn-Trace-Id",
          "scope":"global",
          "replace":"X-Amzn-Trace-Id-Replace"
        }
      ],
      "vars":[
        [
          "status",
          "==",
          200
        ]
      ]
    }
  },
  "upstream":{
    "type":"roundrobin",
    "scheme":"https",
    "nodes":{
      "httpbin.org:443":1
    }
  },
  "uri":"/*"
}'
```

```shell
curl -X GET -i  http://127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
Transfer-Encoding: chunked
X-Server-status: on
X-Server-balancer-addr: 34.206.80.189:443
X-Server-id: 3

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id-Replace": "Root=1-629e0b89-1e274fdd7c23ca6e64145aa2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 117.136.46.203",
  "url": "https://127.0.0.1/get"
}

```

## 删除插件

当你需要禁用 `response-rewrite` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
