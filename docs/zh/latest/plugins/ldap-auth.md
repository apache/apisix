---
title: ldap-auth
keywords:
  - APISIX
  - Plugin
  - LDAP Authentication
  - ldap-auth
description: This document contains information about the Apache APISIX ldap-auth Plugin.
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

`ldap-auth`是用来给路由或服务添加 LDAP 认证的插件，使用 [lualdap](https://lualdap.github.io/lualdap/)连接 LDAP 服务器。

该插件需要与 `consumer` 一起配合使用，API Consumer 可以使用 [basic authentication](https://en.wikipedia.org/wiki/Basic_access_authentication)与 LDAP 服务器进行认证。

## 属性

Consumer 端配置：

| 名称    | 类型   | 必选项 | 描述                                                                      |
| ------- | ------ | -------- | -------------------------------------------------------------------------------- |
| user_dn | string | 是     | LDAP 客户端的用户可分辨名称，例如：`cn=user01,ou=users,dc=example,dc=org`。 |

Route 端配置：

| 名称     | 类型    | 必选项 | 默认值 | 描述                                                            |
|----------|---------|----------|---------|------------------------------------------------------------------------|
| base_dn  | string  | 是     |         | LDAP 服务器的基础可分辨名称，例如：`ou=users,dc=example,dc=org`。|
| ldap_uri | string  | 是     |         | LDAP 服务器的 URI。                                                |
| use_tls  | boolean | 否    | `true`  | 如果设置为 `true` 则表示启用 TLS。                                             |
| uid      | string  | 否    | `cn`    | UID 属性。                                                         |

## 启用插件

首先，你需要创建一个 Consumer 并在其中配置该插件，具体代码如下：

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "ldap-auth": {
            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
        }
    }
}'
```

然后你就可以在指定 Route 或 Service 中启用该插件，具体代码如下：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "ldap-auth": {
            "base_dn": "ou=users,dc=example,dc=org",
            "ldap_uri": "localhost:1389",
            "uid": "cn"
        },
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

按照上文所述进行插件配置后，用户就可以通过授权提出请求并访问 API：

```shell
curl -i -uuser01:password1 http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 OK
...
hello, world
```

如果授权信息请求头丢失或无效，则请求将被拒绝（如下展示了几种返回结果）：

```shell
curl -i http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

```shell
curl -i -uuser:password1 http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

```shell
curl -i -uuser01:passwordfalse http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

## 禁用插件

当你需要禁用 `ldap-auth` 插件时，可以通过以下命令删除相应的 JSON 配置。APISIX 将自动重新加载，无需重启服务：

```shell
curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
