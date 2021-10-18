---
title: authz-casbin
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

## 目录

- [**简介**](#简介)
- [**属性**](#属性)
- [**元数据**](#元数据)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)
- [**示例**](#示例)

## 简介

`authz-casbin` 是一个基于 [Lua Casbin](https://github.com/casbin/lua-casbin/) 的访问控制插件. 该插件支持基于各种访问控制模型的授权场景。

有关如何创建模型和策略的详细文档, 请参阅 [Casbin](https://casbin.org/docs/en/supported-models)。

## 属性

| 名称        | 类型   | 必选项| 默认值 | 有效值 | 描述                                                  |
| ----------- | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| model_path  | string | 必须    |         |       | Casbin 模型配置文件路径。             |
| policy_path | string | 必须    |         |       | Casbin 策略配置文件路径。                          |
| model       | string | 必须    |         |       | 描述 Casbin 的模型定义。               |
| policy      | string | 必须    |         |       | 描述 Casbin 的策略定义。                            |
| username    | string | 必须    |         |       | 描述请求中有可以通过访问控制的用户名The。 |

**注意**: 在插件配置中指定 `model_path`、`policy_path` 和 `username`，或者在插件配置中指定 `model`、 `policy` 和 `username` 来使插件生效。如果你想使用全局的 Casbin 配置，可以先在插件元数据中指定模型和策略，然后插件配置中指定 `username`。通过这种方式可以使所有的路由共享一个配置。

## 元数据

| 名称        | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                            |
| ----------- | ------ | ----------- | ------- | ----- | ---------------------------------------------------------------------- |
| model       | string | 必须    |         |       | 描述 Casbin 的模型定义。                       |
| policy      | string | 必须    |         |       | 描述 Casbin 的策略定义。                                     |

## 如何启用

你可以通过使用模型/策略文件路径或直接在路由中配置模型/策略以启用插件。

### 通过配置文件启用

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "model_path": "/path/to/model.conf",
            "policy_path": "/path/to/policy.csv",
            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

这将在你第一次请求时从模型/策略文件路径中创建一个 Casbin enforcer。

### 通过路由配置启用

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "model": "[request_definition]
            r = sub, obj, act

            [policy_definition]
            p = sub, obj, act

            [role_definition]
            g = _, _

            [policy_effect]
            e = some(where (p.eft == allow))

            [matchers]
            m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

            "policy": "p, *, /, GET
            p, admin, *, *
            g, alice, admin",

            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

这将在你第一次请求时从模型和策略描述中创建一个 Casbin enforcer。

### 通过 plugin metadata 配置模型/策略

首先，发送一个 `PUT` 请求，使用 Admin API 将模型和策略配置信息添加到插件的元数据中。所有通过这种插件的方式创建的路由都会带有一个带插件元数据配置的 Casbin enforcer。同时也可以使用 `PUT` 请求修改模型和策略配置信息，Apache APISIX 会自动读取最新的配置。

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/authz-casbin -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
"model": "[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

"policy": "p, *, /, GET
p, admin, *, *
g, alice, admin"
}'
```

然后通过发送以下请求将这个插件添加到一个路由上。注意，现在不再需要添加模型/策略的详细描述。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

**注意**: 插件路由配置比插件元数据配置有更高的优先权。因此，如果模型/策略配置存在于插件路由配置中，插件将使用它而不是元数据配置。

## 测试插件

我们将定义模型为:

```conf
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)
```

并应用该策略:

```conf
p, *, /, GET
p, admin, *, *
g, alice, admin
```

这意味着任何人都可以使用 `GET` 请求方法访问主页（`/`），而只有具有管理权限的用户可以访问其他页面和使用其他请求方法。

例如，在这里，任何人都可以用GET请求方法访问主页，请求正常进行。

```shell
curl -i http://127.0.0.1:9080/ -X GET
```

如果一些未经授权的用户 `bob` 试图访问任何其他页面，他们将得到一个403错误:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: bob' -X GET
HTTP/1.1 403 Forbidden
```

但是像 `alice` 这样有管理权限的人可以访问它。

```shell
curl -i http://127.0.0.1:9080/res -H 'user: alice' -X GET
```

## 禁用插件

在插件配置中删除相应的 json 配置，以禁用 `authz-casbin` 插件。由于 Apache APISIX 插件是热加载的，因此不需要重新启动 Apache APISIX。

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 示例

查看模型和策略使用的例子 [here](https://github.com/casbin/lua-casbin/tree/master/examples)。
