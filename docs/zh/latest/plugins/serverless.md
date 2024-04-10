---
title: serverless
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Serverless
description: 本文介绍了关于 API 网关 Apache APISIX serverless-pre-function 和 serverless-post-function 插件的基本信息及使用方法。
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

APISIX 有两个 `serverless` 插件：`serverless-pre-function` 和 `serverless-post-function`。

`serverless-pre-function` 插件会在指定阶段开始时运行，`serverless-post-function` 插件会在指定阶段结束时运行。这两个插件使用相同的属性。

## 属性

| 名称      | 类型          | 必选项   | 默认值     | 有效值                                                                       | 描述                                                                            |
| --------- | ------------- | ------- | ---------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| phase     | string        | 否      | ["access"] | ["rewrite", "access", "header_filter", "body_filter", "log", "before_proxy"] | 执行 serverless 函数的阶段。                                                     |
| functions | array[string] | 是      |            |                                                                              | 指定运行的函数列表。该属性可以包含一个函数，也可以是多个函数，按照先后顺序执行。    |

:::info 重要

此处仅接受函数，不接受其他类型的 Lua 代码。

比如匿名函数是合法的：

```lua
return function()
    ngx.log(ngx.ERR, 'one')
end
```

闭包也是合法的：

```lua
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

但不是函数类型的代码就是非法的：

```lua
local count = 1
ngx.say(count)
```

:::

:::note 注意

从 `v2.6` 版本开始，`conf` 和 `ctx` 作为前两个参数传递给 `serverless` 函数。

在 `v2.12.0` 版本之前，`before_proxy` 阶段曾被称作 `balancer`。考虑到这一方法是在 `access` 阶段之后、请求到上游之前运行，并且与 `balancer` 没有关联，因此已经更新为 `before_proxy`。

:::

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions" : ["return function() ngx.log(ngx.ERR, \"serverless pre function\"); end"]
        },
        "serverless-post-function": {
            "phase": "rewrite",
            "functions" : ["return function(conf, ctx) ngx.log(ngx.ERR, \"match uri \", ctx.curr_req_matched and ctx.curr_req_matched._path); end"]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/index.html
```

如果你在 `./logs/error.log` 中发现 `serverless pre function` 和 `match uri /index.html` 两个 error 级别的日志，表示指定的函数已经生效。

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
