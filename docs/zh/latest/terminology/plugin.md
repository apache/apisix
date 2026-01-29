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

<br />
<div style={{textAlign: 'center'}}>
<img src="https://static.apiseven.com/uploads/2023/03/09/ZsH5C8Og_plugins-phases.png" alt="Routes Diagram" width="50%"/>
</div>
<br />

## 插件执行顺序

通常情况下，插件按照以下顺序执行：

1. [全局规则](./global-rule.md) 插件
   1. rewrite 阶段的插件
   2. access 阶段的插件

2. 绑定到其他对象的插件
   1. rewrite 阶段的插件
   2. access 阶段的插件

在每个阶段内，你可以在插件的 `_meta.priority` 字段中可选地定义一个新的优先级数，该优先级数优先于默认插件优先级在执行期间。具有更高优先级数的插件首先执行。

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
| filter         | array         | 根据请求的参数，在运行时控制插件是否执行。此配置由一个或多个 {var, operator, val} 元素组成列表，类似：`{{var, operator, val}, {var, operator, val}, ...}}`。例如 `{"arg_version", "==", "v2"}`，表示当前请求参数 `version` 是 `v2`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致。操作符的使用方法，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。|

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
