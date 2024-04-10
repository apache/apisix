---
title: ldap-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - LDAP Authentication
  - ldap-auth
description: 本篇文档介绍了 Apache APISIX ldap-auth 插件的相关信息。
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

`ldap-auth` 插件可用于给路由或服务添加 LDAP 身份认证，该插件使用 [lua-resty-ldap](https://github.com/api7/lua-resty-ldap) 连接 LDAP 服务器。

该插件需要与 Consumer 一起配合使用，API 的调用方可以使用 [basic authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) 与 LDAP 服务器进行认证。

## 属性

Consumer 端：

| 名称    | 类型   | 必选项 | 描述                                                                      |
| ------- | ------ | -------- | -------------------------------------------------------------------------------- |
| user_dn | string | 是     | LDAP 客户端的 dn，例如：`cn=user01,ou=users,dc=example,dc=org`。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。 |

Route 端：

| 名称     | 类型    | 必选项 | 默认值 | 描述                                                            |
|----------|---------|----------|---------|------------------------------------------------------------------------|
| base_dn  | string  | 是     |         | LDAP 服务器的 dn，例如：`ou=users,dc=example,dc=org`。|
| ldap_uri | string  | 是     |         | LDAP 服务器的 URI。                                                |
| use_tls  | boolean | 否    | false  | 如果设置为 `true` 则表示启用 TLS。                                             |
| tls_verify| boolean  | 否     | false        | 是否校验 LDAP 服务器的证书。如果设置为 `true`，你必须设置 `config.yaml` 里面的 `ssl_trusted_certificate`，并且确保 `ldap_uri` 里的 host 和服务器证书中的 host 匹配。 |
| uid      | string  | 否    | cn    | UID 属性。                                                         |

## 启用插件

首先，你需要创建一个 Consumer 并在其中配置该插件，具体代码如下：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "ldap-auth": {
            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
        }
    }
}'
```

然后就可以在指定路由或服务中启用该插件，具体代码如下：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

通过上述方法配置插件后，可以通过以下命令测试插件：

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
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

```shell
curl -i -uuser:password1 http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

```shell
curl -i -uuser01:passwordfalse http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

## 删除插件

当你需要禁用 `ldap-auth` 插件时，可以通过以下命令删除相应的 JSON 配置。APISIX 将自动重新加载，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
