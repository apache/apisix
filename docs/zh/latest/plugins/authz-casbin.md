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

## 描述

`authz-casbin` 是一个基于 [Lua Casbin](https://github.com/casbin/lua-casbin/) 的访问控制插件，该插件支持基于各种访问控制模型的授权场景。

有关如何创建鉴权模型和鉴权策略的详细文档, 请参阅 [Casbin](https://casbin.org/docs/en/supported-models)。

## 属性

| 名称         | 类型    | 必选项 |  默认值  | 有效值 | 描述                            |
| ----------- | ------ | ------ | ------- | ----- | ---------------------------    |
| model_path  | string | 必须    |         |       | Casbin 鉴权模型配置文件路径       |
| policy_path | string | 必须    |         |       | Casbin 鉴权策略配置文件路径       |
| model       | string | 必须    |         |       | Casbin 鉴权模型的文本定义         |
| policy      | string | 必须    |         |       | Casbin 鉴权策略的文本定义         |
| username    | string | 必须    |         |       | 描述请求中有可以通过访问控制的用户名 |

**注意**: 在插件配置中指定 `model_path`、`policy_path` 和 `username`，或者在插件配置中指定 `model`、`policy` 和 `username` 来使插件生效。如果想要使所有的路由共享 Casbin 配置，可以先在插件元数据中指定鉴权模型和鉴权策略，然后在指定路由的插件配置中指定 `username`。

## 元数据

| 名称         | 类型    | 必选项  | 默认值 | 有效值 | 描述                       |
| ----------- | ------ | ------ | ----- | ----- |  ------------------        |
| model       | string | 必须    |       |       | Casbin 鉴权模型的文本定义     |
| policy      | string | 必须    |       |       | Casbin 鉴权策略的文本定义     |

## 如何启用

该插件可以通过在任意路由上配置 `鉴权模型/鉴权策略文件路径` 或 `鉴权模型/鉴权策略文本` 来启用。

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

上述请求会根据鉴权模型/鉴权策略文件中的定义创建一个 Casbin enforcer。

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

上述请求会根据鉴权模型和鉴权策略的定义创建一个 Casbin enforcer。

### 通过 plugin metadata 配置模型/策略

首先，使用 Admin API 发送一个 `PUT` 请求，将鉴权模型和鉴权策略的配置信息添加到插件的元数据中。所有通过这种方式创建的路由都会带有一个带插件元数据配置的 Casbin enforcer。同时也可以使用 `PUT` 请求更新鉴权模型和鉴权策略配置信息，该插件将会自动同步最新的配置信息。

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

通过发送以下请求可以将该插件添加到路由上。注意，此处只需要配置 `username`，不需要再增加鉴权模型/鉴权策略的定义。

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

**注意**: 插件路由配置比插件元数据配置有更高的优先级。因此，如果插件路由配置中存在鉴权模型/鉴权策略配置，插件将优先使用插件路由的配置而不是插件元数据中的配置。

## 测试插件

首先定义测试鉴权模型:

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

然后添加测试鉴权策略:

```conf
p, *, /, GET
p, admin, *, *
g, alice, admin
```

以上授权策略规定了任何人都可以使用 `GET` 请求方法访问主页（`/`），而只有具有管理权限的用户可以访问其他页面和使用其他请求方法。

例如，在这里，任何人都可以用 `GET` 请求方法访问主页，返回正常。

```shell
curl -i http://127.0.0.1:9080/ -X GET
```

未经授权的用户如 `bob` 访问除 `/` 以外的任何其他页面将得到一个 403 错误:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: bob' -X GET
HTTP/1.1 403 Forbidden
```

拥有管理权限的人 `alice` 则可以访问其它页面。

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

更多鉴权模型和鉴权策略使用的例子请参考 [Casbin 示例](https://github.com/casbin/lua-casbin/tree/master/examples)。
