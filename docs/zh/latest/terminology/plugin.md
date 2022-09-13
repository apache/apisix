---
title: Plugin
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

`Plugin` 表示将在 `HTTP` 请求/响应生命周期期间执行的插件配置。

`Plugin` 配置可直接绑定在 `Route` 上，也可以被绑定在 `Service`、`Consumer` 或 `Plugin Config` 上。而对于同一个插件的配置，只能有一份是有效的，配置选择优先级总是 `Consumer` > `Route` > `Plugin Config` > `Service`。

在 `conf/config.yaml` 中，可以声明本地 APISIX 节点都支持哪些插件。这是个白名单机制，不在该白名单的插件配置，都将会被自动忽略。这个特性可用于临时关闭或打开特定插件，应对突发情况非常有效。
如果你想在现有插件的基础上新增插件，注意需要拷贝 `conf/config-default.yaml` 的插件节点内容到 `conf/config.yaml` 的插件节点中。

一个插件在一次请求中只会执行一次，即使被同时绑定到多个不同对象中（比如 Route 或 Service）。
插件运行先后顺序是根据插件自身的优先级来决定的，例如：

```lua
local _M = {
    version = 0.1,
    priority = 0, -- 这个插件的优先级为 0
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

插件配置可存放于 Route 或 Service 中，键为 `plugins`，值是包含多个插件配置的对象。对象内部用插件名字作为 key 来保存不同插件的配置项。

如下所示的配置中，包含 `limit-count` 和 `prometheus` 两种插件的配置：

```json
{
    ...
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    }
}
```

并不是所有插件都有具体配置项，比如 `prometheus` 下是没有任何具体配置项，这时候用一个空的对象标识即可。

如果一个请求因为某个插件而被拒绝，会有类似这样的 warn 日志：`ip-restriction exits with http status code 403`。

## 插件通用配置

通过 `_meta` 配置项可以将一些通用的配置应用于插件，具体配置项如下：

| 名称         | 类型 | 描述           |
|--------------|------|----------------|
| disable | boolean  | 是否禁用该插件。 |
| error_response | string/object  | 自定义错误响应。 |
| priority       | integer        | 自定义插件优先级。 |
| filter  | array   | 根据请求的参数，在运行时控制插件是否执行。此配置由一个或多个 {var, operator, val} 元素组成列表，类似：{{var, operator, val}, {var, operator, val}, ...}}。例如 `{"arg_version", "==", "v2"}`，表示当前请求参数 `version` 是 `v2`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致。操作符的具体用法请看[lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 operator-list 部分。|

### 禁用插件

通过 `disable` 配置，你可以新增一个处于禁用状态的插件，请求不会经过该插件。

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

通过 `error_response` 配置，可以将任意插件的错误响应配置成一个固定的值，避免因为插件内置的错误响应信息而带来困扰。

如下配置表示将 `jwt-auth` 插件的错误响应自定义为 '{"message": "Missing credential in request"}'。

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

所有插件都有默认优先级，但你仍可以通过 `priority` 配置项来自定义插件优先级，从而改变插件执行顺序。

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

serverless-pre-function 的默认优先级是 10000，serverless-post-function 的默认优先级是 -2000。默认情况下会先执行 serverless-pre-function 插件，再执行 serverless-post-function 插件。

上面的配置意味着将 serverless-pre-function 插件的优先级设置为 -2000，serverless-post-function 插件的优先级设置为 10000。serverless-post-function 插件会先执行，再执行 serverless-pre-function 插件。

注意：

- 自定义插件优先级只会影响插件实例绑定的主体，不会影响该插件的所有实例。比如上面的插件配置属于路由 A ，路由 B 上的插件 serverless-post-function 和 serverless-post-function 插件执行顺序不会受到影响，会使用默认优先级。
- 自定义插件优先级不适用于 consumer 上配置的插件的 rewrite 阶段。路由上配置的插件的 rewrite 阶段将会优先运行，然后才会运行 consumer 上除 auth 插件之外的其他插件的 rewrite 阶段。

### 动态控制插件是否执行

默认情况下，在路由中指定的插件都会被执行。但是我们可以通过 `filter` 配置项为插件添加一个过滤器，通过过滤器的执行结果控制插件是否执行。

如下配置表示，只有当请求查询参数中 `version` 值为 `v2` 时，`proxy-rewrite` 插件才会执行。

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

使用下述配置创建一条完整的路由：

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

当请求中不带任何参数时，`proxy-rewrite` 插件不会执行，请求将被转发到上游的 `/get`:

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

当请求中携带参数 `version=v2` 时，`proxy-rewrite` 插件执行，请求将被转发到上游的 `/anything`:

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

只需要通过 admin API 发送一个 HTTP 请求即可：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

注意：如果你已经在路由规则里配置了某个插件（比如在 `route` 的 `plugins` 字段里面添加了它），然后禁用了该插件，在执行路由规则的时候会跳过这个插件。

## stand-alone 模式下的热加载

参考 [stand alone 模式](../stand-alone.md) 文档里关于配置插件的内容。
