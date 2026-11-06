---
title: Plugin
keywords:
  - API 网关
  - Apache APISIX
  - 插件
  - 插件优先级
description: 本文介绍了 APISIX Plugin 对象的相关信息及其使用方法，并且介绍了如何自定义插件优先级、自定义错误响应、动态控制插件执行状态等。
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

APISIX 插件可以扩展 APISIX 的功能，以满足组织或用户特定的流量管理、可观测性、安全、请求/响应转换、无服务器计算等需求。

APISIX 提供了许多现有的插件，可以定制和编排以满足你的需求。这些插件可以全局启用，以在每个传入请求上触发，也可以局部绑定到其他对象，例如在 [Route](./route.md)、[Service](./service.md)、[Consumer](./consumer.md) 或 [Plugin Config](./plugin-config.md) 上。你可以参考 [Admin API](../admin-api.md#plugin) 了解如何使用该资源。

如果现有的 APISIX 插件不满足需求，你还可以使用 Lua 或其他语言（如 Java、Python、Go 和 Wasm）编写自定义插件。

## 插件安装

默认情况下，大多数 APISIX 插件都已[安装](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua)：

```lua title="apisix/cli/config.lua"
local _M = {
  ...
  plugins = {
    "real-ip",
    "ai",
    "client-control",
    "proxy-control",
    "request-id",
    "zipkin",
    "ext-plugin-pre-req",
    "fault-injection",
    "mocking",
    "serverless-pre-function",
    ...
  },
  ...
}
```

如果您想调整插件安装，请将自定义的 `plugins` 配置添加到 `config.yaml` 中。例如：

```yaml
plugins:
  - real-ip                   # 安装
  - ai
  - client-control
  - proxy-control
  - request-id
  - zipkin
  - ext-plugin-pre-req
  - fault-injection
  # - mocking                 # 不安装
  - serverless-pre-function
  ...                         # 其它插件
```

完整配置参考请参见 [`config.yaml.example`](https://github.com/apache/apisix/blob/master/conf/config.yaml.example)。

重新加载 APISIX 以使配置更改生效。

## 插件执行生命周期

安装的插件首先会被初始化。然后会检查插件的配置，以确保插件配置遵循定义的[JSON Schema](https://json-schema.org)。

当一个请求通过 APISIX 时，插件的相应方法会在以下一个或多个阶段中执行： `rewrite`, `access`, `before_proxy`, `header_filter`, `body_filter`, and `log`。这些阶段在很大程度上受到[OpenResty 指令](https://openresty-reference.readthedocs.io/en/latest/Directives/)的影响。

## 插件执行顺序

对于匹配 HTTP Route 的请求，全局规则插件和局部绑定的插件会按阶段交错执行：

1. 全局规则插件的 `rewrite` 阶段；
2. 局部绑定插件的 `rewrite` 阶段；
3. 全局规则插件的 `access` 阶段；
4. 局部绑定插件的 `access` 阶段。

局部绑定插件的 `rewrite` 处理函数会先于所有全局规则插件的 `access` 处理函数执行。如果某个 `rewrite` 处理函数终止了请求，则排在它之后的 `access` 处理函数不会执行，但 `log` 处理函数仍会执行。

在上述每个分组内，你可以在插件的 `_meta.priority` 字段中定义新的优先级数，该优先级会在执行时覆盖插件的默认优先级。优先级数越高，插件越先执行。优先级不会使插件跨越阶段或全局、局部分组执行。

例如，如果你想在请求到达路由时，让 `limit-count`（优先级 1002）先于 `ip-restriction`（优先级 3000）运行，可以通过将更高的优先级数传递给 `limit-count` 的 `_meta.priority` 字段来实现：

```json
{
  ...,
  "plugins": {
    "limit-count": {
      ...,
      "_meta": {
        "priority": 3010
      }
    }
  }
}
```

若要将此插件实例的优先级重置为默认值，只需从插件配置中删除`_meta.priority`字段即可。

## 插件合并优先顺序

当同一个插件在全局规则中和局部规则（例如路由）中同时配置时，两个插件将顺序执行。

然而，如果相同的插件在多个对象上本地配置，例如在[`Route`](route.md), [`Service`](service.md), [`Consumer`](consumer.md) 或[`Plugin Config`](plugin-config.md) 上，每个非全局插件只会执行一次，因为在执行期间，针对特定的优先顺序，这些对象中配置的插件会被合并：

`Consumer`  > `Consumer Group` > `Route` > `Plugin Config` > `Service`

因此，如果相同的插件在不同的对象中具有不同的配置，则合并期间具有最高优先顺序的插件配置将被使用。

## 通用配置

通过 `_meta` 配置项可以将一些通用的配置应用于插件，你可以参考下文使用这些通用配置。通用配置如下：

| 名称           | 类型           |     描述       |
|--------------- |-------------- |----------------|
| disable        | boolean       | 当设置为 `true` 时，则禁用该插件。可选值为 `true` 和 `false`。 |
| error_response | string/object | 自定义错误响应。 |
| priority       | integer       | 自定义插件优先级。 |
| filter         | array         | 根据请求的参数，在运行时控制插件是否执行。此配置由一个或多个 {var, operator, val} 元素组成列表，类似：`{{var, operator, val}, {var, operator, val}, ...}}`。例如 `{"arg_version", "==", "v2"}`，表示当前请求参数 `version` 是 `v2`。这里的 `var` 与 NGINX 内部自身变量命名保持一致。条件格式和支持的操作符请参考 [APISIX 表达式](../router-radixtree.md#如何通过-nginx-内置变量过滤路由)。|
| filter_phase   | string        | 计算 `filter` 的阶段，可选值为 `access`、`before_proxy`、`lua_body_filter`、`header_filter`、`body_filter`、`log`。必须与 `filter` 一起配置。详见[在后续阶段计算过滤器](#在后续阶段计算过滤器)。|

### 禁用指定插件

通过 `disable` 参数，你可以将某个插件调整为“禁用状态”，即请求不会经过该插件。

```json
{
    "proxy-rewrite": {
        "_meta": {
            "disable": true
        }
    }
}
```

### 自定义错误响应

通过 `error_response` 配置，可以将任意插件的错误响应配置成一个固定的值，避免因为插件内置的错误响应信息而带来不必要的麻烦。

如下配置表示将 `jwt-auth` 插件的错误响应自定义为 `Missing credential in request`。

```json
{
    "jwt-auth": {
        "_meta": {
            "error_response": {
                "message": "Missing credential in request"
            }
        }
    }
}
```

### 自定义插件优先级

所有插件都有默认优先级，但是你仍然可以通过 `priority` 配置项来自定义插件优先级，从而改变插件执行顺序。

```json
 {
    "serverless-post-function": {
        "_meta": {
            "priority": 10000
        },
        "phase": "rewrite",
        "functions" : ["return function(conf, ctx)
                    ngx.say(\"serverless-post-function\");
                    end"]
    },
    "serverless-pre-function": {
        "_meta": {
            "priority": -2000
        },
        "phase": "rewrite",
        "functions": ["return function(conf, ctx)
                    ngx.say(\"serverless-pre-function\");
                    end"]
    }
}
```

`serverless-pre-function` 的默认优先级是 `10000`，`serverless-post-function` 的默认优先级是 `-2000`。默认情况下会先执行 `serverless-pre-function` 插件，再执行 `serverless-post-function` 插件。

上面的配置则将 `serverless-pre-function` 插件的优先级设置为 `-2000`，`serverless-post-function` 插件的优先级设置为 `10000`，因此 `serverless-post-function` 插件会优先执行。

:::note 注意

- 自定义插件优先级只会影响插件实例绑定的主体，不会影响该插件的所有实例。比如上面的插件配置属于路由 A，路由 B 上的插件 `serverless-post-function` 和 `serverless-post-function` 插件执行顺序不会受到影响，会使用默认优先级。
- 自定义插件优先级不适用于 Consumer 上配置的插件的 `rewrite` 阶段。路由上配置的插件的 `rewrite` 阶段将会优先运行，然后才会运行 Consumer 上除 `auth` 类插件之外的其他插件的 `rewrite` 阶段。

:::

### 动态控制插件执行状态

默认情况下，在路由中指定的插件都会被执行。但是你可以通过 `filter` 配置项为插件添加一个过滤器，通过过滤器的执行结果控制插件是否执行。

1. 如下配置表示，只有当请求查询参数中 `version` 值为 `v2` 时，`proxy-rewrite` 插件才会执行。

    ```json
    {
        "proxy-rewrite": {
            "_meta": {
                "filter": [
                    ["arg_version", "==", "v2"]
                ]
            },
            "uri": "/anything"
        }
    }
    ```

2. 使用下述配置创建一条完整的路由。

    ```json
    {
        "uri": "/get",
        "plugins": {
            "proxy-rewrite": {
                "_meta": {
                    "filter": [
                        ["arg_version", "==", "v2"]
                    ]
                },
                "uri": "/anything"
            }
        },
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "httpbin.org:80": 1
            }
        }
    }
    ```

3. 当请求中不带任何参数时，`proxy-rewrite` 插件不会执行，请求将被转发到上游的 `/get`。

    ```shell
    curl -v /dev/null http://127.0.0.1:9080/get -H"host:httpbin.org"
    ```

    ```shell
    < HTTP/1.1 200 OK
    ......
    < Server: APISIX/2.15.0
    <
    {
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Host": "httpbin.org",
        "User-Agent": "curl/7.79.1",
        "X-Amzn-Trace-Id": "Root=1-62eb6eec-46c97e8a5d95141e621e07fe",
        "X-Forwarded-Host": "httpbin.org"
    },
    "origin": "127.0.0.1, 117.152.66.200",
    "url": "http://httpbin.org/get"
    }
    ```

4. 当请求中携带参数 `version=v2` 时，`proxy-rewrite` 插件执行，请求将被转发到上游的 `/anything`:

    ```shell
    curl -v /dev/null http://127.0.0.1:9080/get?version=v2 -H"host:httpbin.org"
    ```

    ```shell
    < HTTP/1.1 200 OK
    ......
    < Server: APISIX/2.15.0
    <
    {
    "args": {
        "version": "v2"
    },
    "data": "",
    "files": {},
    "form": {},
    "headers": {
        "Accept": "*/*",
        "Host": "httpbin.org",
        "User-Agent": "curl/7.79.1",
        "X-Amzn-Trace-Id": "Root=1-62eb6f02-24a613b57b6587a076ef18b4",
        "X-Forwarded-Host": "httpbin.org"
    },
    "json": null,
    "method": "GET",
    "origin": "127.0.0.1, 117.152.66.200",
    "url": "http://httpbin.org/anything?version=v2"
    }
    ```

### 在后续阶段计算过滤器

默认情况下，`filter` 在每个请求中只计算一次，时机是插件第一个运行的函数，其结果适用于插件后续的所有函数。因此对于带有 `access` 函数的插件（比如日志类插件），决定是在请求被代理之前做出的，此时 `status` 和 `upstream_status` 还没有值。

`filter_phase` 用于指定做出决定的阶段，可选值为 `access`、`before_proxy`、`lua_body_filter`、`header_filter`、`body_filter`、`log`。未配置时，行为没有任何变化。

- 插件在 `filter_phase` 之前的阶段中的函数总是会执行，与过滤器的结果无关。
- `filter_phase` 运行时计算一次过滤器。结果为 `false` 时，该函数以及插件后续的所有函数在本次请求中都会被跳过。
- 如果 `filter_phase` 在本次请求中没有运行，则不会做出决定，插件后续的所有函数都会执行。不会回退到其他阶段，包括 `log`。

如果没有配置 `filter`，或者插件没有与 `filter_phase` 同名的函数，配置会被拒绝。

指定的阶段被跳过是正常且受支持的行为。例如：

- `HEAD` 请求会运行 `header_filter`，但不会运行 `body_filter`，因此 `body_filter` 不会做出决定。上游返回的 204 或 304 响应会运行 `body_filter`。
- 客户端在响应头返回之前关闭连接（状态码 499）时，`header_filter` 和 `body_filter` 都不会运行。
- 插件在 `rewrite` 阶段直接响应（比如 `key-auth` 返回 401）时会跳过 `access`，因此 `access` 不会做出决定。插件在 `access` 阶段直接响应时会跳过 `before_proxy`。
- `upstream.scheme` 为 `ws` 或 `wss` 的路由不会运行 `header_filter` 和 `body_filter`，因此它们不会做出决定。使用 `enable_websocket` 的路由会运行这两个阶段。
- Stream 路由运行 `preread`、`before_proxy` 和 `log`，因此只有 `before_proxy` 和 `log` 能做出决定。

下面的配置会记录除 APISIX 或其插件生成的 404 之外的所有响应，并保留上游返回的 404。这里用正则表达式匹配 `upstream_status`，因为重试之后它是一个列表，比如 `502, 404`：

```json
{
    "file-logger": {
        "path": "logs/file.log",
        "include_resp_body": true,
        "_meta": {
            "filter": ["OR", ["status", "~=", 404], ["upstream_status", "~~", "404$"]],
            "filter_phase": "body_filter"
        }
    }
}
```

对于日志类插件，当过滤器读取 `status` 或 `upstream_status` 时使用 `body_filter`，被排除的请求不会缓存响应体。没有运行 `body_filter` 的请求无论过滤器结果如何都会被记录，因此使用 `body_filter` 且“只记录 5xx”的日志插件仍然会记录 `HEAD` 请求。精确过滤需要使用 `log`，过滤器读取 `bytes_sent`、`body_bytes_sent`、`upstream_response_time` 或 `request_time` 时也应使用它。使用 `log` 且开启 `include_resp_body` 时，被排除的请求也会缓存响应体，除非在 `include_resp_body_expr` 中重复该条件。

下表列出了一些常用变量及其最早有意义的阶段，并非完整列表。

| 变量 | 最早有意义的阶段 | 说明 |
|------|------------------|------|
| `arg_*`、`http_*`、`uri`、`request_method`、`remote_addr`、`host`、`route_id` | `rewrite` | 不需要配置 `filter_phase`。 |
| `consumer_name` | `access` | 在 `rewrite` 阶段只对运行在认证插件之后的插件有值。 |
| `balancer_ip` | `before_proxy` | |
| `status` | `header_filter` | |
| `upstream_status`、`upstream_addr`、`upstream_http_*` | `header_filter` | 响应由 APISIX 生成时为空。 |
| `sent_http_*` | `header_filter` | |
| `upstream_response_time`、`bytes_sent`、`body_bytes_sent`、`request_time` | `log` | 在此之前读取会得到 `0` 或中间值。 |

#### 不支持的配置

`filter_phase` 无法让插件在较早阶段的行为取决于只有之后才存在的信息：指定阶段之前的函数总是会执行。下面这些配置是设计上明确不支持的，其结果不是 Bug。

要判断未列出的插件，请查看它在哪些阶段有函数，以及每个函数做了什么。`filter_phase` 适合较早函数只做状态准备的插件。如果较早的函数有以下行为，请不要使用：

- 响应或拒绝请求，此时再做决定已经来不及阻止。
- 获取资源并由后续函数释放，决定为 `false` 时释放会被跳过。
- 产生请求之外的影响，比如复制请求或上报数据。
- 开始了必须由后续函数完成的工作，决定为 `false` 时工作只完成一半。

| 插件 | `filter` | `filter_phase` | 结果 |
|------|----------|----------------|------|
| `limit-conn` | `status ~= 500` | `log` | 连接在 `access` 阶段获取，500 响应之后不会释放，后续请求返回 503。 |
| `csrf` | 豁免带有指定请求头的请求 | `header_filter` | 校验在 `access` 阶段执行，被豁免但没有 token 的 `POST` 请求返回 401。 |
| `cors` | 结果为 `false` | `header_filter` | `OPTIONS` 请求仍然在 `rewrite` 阶段直接返回空的 200，不会到达上游。 |
| `proxy-mirror` | 结果为 `false` | `before_proxy` | 镜像在 `rewrite` 阶段设置，被排除的请求仍然会被镜像。 |
| `grpc-web` | 结果为 `false` | `header_filter` | 方法校验在 `access` 阶段执行，`GET` 请求返回 405。 |
| `ai-proxy` | 结果为 `false` | `before_proxy` | `access` 阶段接管了代理而 `before_proxy` 又被跳过，请求返回 500。 |
| `zipkin` | `status >= 500` | `log` | 被排除的请求仍然会向上游发送追踪请求头，并上报在 `log` 之前已结束的 span（`apisix.proxy`；`span_version` 为 1 时是 `apisix.rewrite` 和 `apisix.access`），但缺少它们的父 span。 |
| `brotli` | `status == 200` | `body_filter` | `header_filter` 阶段同样为 404 声明了 `Content-Encoding: br`，而其响应体未经压缩就发出。请改用更早的阶段：使用 `header_filter` 时，200 会被压缩，404 不受影响。 |

## 热加载

APISIX 的插件是热加载的，不管你是新增、删除还是修改插件，都不需要重启服务。

只需要通过 Admin API 发送一个 HTTP 请求即可：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```

:::note 注意

如果你已经在路由规则里配置了某个插件（比如在 Route 的 `plugins` 字段里面添加了它），然后在配置文件中禁用了该插件，在执行路由规则时则会跳过该插件。

:::

## Standalone 模式下的热加载

关于 Stand Alone 模式下的热加载的信息，请参考 [stand alone 模式](../../../en/latest/deployment-modes.md#standalone)。
