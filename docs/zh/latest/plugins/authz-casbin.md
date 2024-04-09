---
title: authz-casbin
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Authz Casbin
  - authz-casbin
description: 本文介绍了关于 Apache APISIX `authz-casbin` 插件的基本信息及使用方法。
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

`authz-casbin` 插件是一个基于 [Lua Casbin](https://github.com/casbin/lua-casbin/) 的访问控制插件，该插件支持各种 [access control models](https://casbin.org/docs/en/supported-models) 的强大授权场景。

## 属性

| 名称         | 类型    | 必选项 | 描述                               |
| ----------- | ------ | ------- | ---------------------------------- |
| model_path  | string | 是      | Casbin 鉴权模型配置文件路径。        |
| policy_path | string | 是      | Casbin 鉴权策略配置文件路径。        |
| model       | string | 是      | Casbin 鉴权模型的文本定义。          |
| policy      | string | 是      | Casbin 鉴权策略的文本定义。          |
| username    | string | 是      | 描述请求中有可以通过访问控制的用户名。 |

:::note

你必须在插件配置中指定 `model_path`、`policy_path` 和 `username` 或者指定 `model`、`policy` 和 `username` 才能使插件生效。

如果你想要使所有的 Route 共享 Casbin 配置，你可以先在插件元数据中指定 `model` 和 `policy`，在插件配置中仅指定 `username`，这样所有 Route 都可以使用 Casbin 插件配置。

::::

## 元数据

| 名称        | 类型    | 必选项  | 描述                           |
| ----------- | ------ | ------- | ------------------------------|
| model       | string | 是      | Casbin 鉴权模型的文本定义。     |
| policy      | string | 是      | Casbin 鉴权策略的文本定义。     |

## 启用插件

你可以使用 model/policy 文件路径或使用插件 configuration/metadata 中的 model/policy 文本配置在 Route 上启用插件。

### 通过 model/policy 文件路径启用插件

以下示例展示了通过 model/policy 配置文件来设置 Casbin 身份验证：

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

### 通过 model/policy 文本配置启用插件

以下示例展示了通过你的 model/policy 文本来设置 Casbin 身份验证：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

### 通过 plugin metadata 配置模型/策略

首先，我们需要使用 Admin API 发送一个 `PUT` 请求，将 `model` 和 `policy` 的配置添加到插件的元数据中。

所有通过这种方式创建的 Route 都会带有一个带插件元数据配置的 Casbin enforcer。你也可以使用这种方式更新 model/policy，该插件将会自动同步最新的配置信息。

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/authz-casbin \
-H "X-API-KEY: $admin_key" -i -X PUT -d '
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

更新插件元数据后，可以将插件添加到指定 Route 中：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

:::note

插件路由的配置比插件元数据的配置有更高的优先级。因此，如果插件路由的配置中存在 model/policy 配置，插件将优先使用插件路由的配置而不是插件元数据中的配置。

:::

## 测试插件

首先定义测试鉴权模型：

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

然后添加测试鉴权策略：

```conf
p, *, /, GET
p, admin, *, *
g, alice, admin
```

如果想要了解更多关于 `policy` 和 `model` 的配置，请参考 [examples](https://github.com/casbin/lua-casbin/tree/master/examples)。

上述配置将允许所有人使用 `GET` 请求访问主页（`/`），而只有具有管理员权限的用户才可以访问其他页面并使用其他请求方法。

简单举例来说，假设我们向主页发出 `GET` 请求，通常都可以返回正常结果。

```shell
curl -i http://127.0.0.1:9080/ -X GET
```

但如果是一个未经授权的普通用户（例如：`bob`）访问除 `/` 以外的其他页面，将得到一个 403 错误：

```shell
curl -i http://127.0.0.1:9080/res -H 'user: bob' -X GET
```

```
HTTP/1.1 403 Forbidden
```

而拥有管理权限的用户（如 `alice`）则可以访问其它页面。

```shell
curl -i http://127.0.0.1:9080/res -H 'user: alice' -X GET
```

## 删除插件

当你需要禁用 `authz-casbin` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
