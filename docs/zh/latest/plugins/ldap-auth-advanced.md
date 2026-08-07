---
title: ldap-auth-advanced
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - LDAP Authentication
  - LDAP Groups
  - ldap-auth-advanced
description: ldap-auth-advanced 插件通过“先搜索后绑定”的方式在 LDAP 目录中认证用户，收集用户所属的用户组，并可基于用户组成员关系对请求进行鉴权。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ldap-auth-advanced" />
</head>

## 描述

`ldap-auth-advanced` 插件可用于给路由或服务添加 LDAP 身份认证。与使用 Consumer 配置拼接 DN 后直接绑定的 [`ldap-auth`](./ldap-auth.md) 不同，该插件会先在目录中**搜索**用户，再以搜索到的条目进行绑定。因此无需在 APISIX 中逐个维护用户，插件还可以收集用户所属的用户组，用于鉴权以及向上游服务传递身份信息。

插件在每个请求中依次执行以下操作：

1. 从 `Proxy-Authorization` 请求头中读取凭证，若不可用则回退到 `Authorization`。
2. 在 `base_dn` 子树中搜索 `attribute` 与用户名匹配的条目，并使用请求中的密码以该条目进行绑定。
3. 收集用户所属的用户组：默认从用户条目的 `memberOf` 属性读取，也可以通过 `group_base_dn` 搜索用户组子树获得。
4. 如果配置了 `groups_required`，则校验用户组成员关系。
5. 关联匹配的 [Consumer](../terminology/consumer.md)，除非 `consumer_required` 设置为 `false`。
6. 将用户组名称通过 `X-Authenticated-Groups` 请求头添加到请求中。

凭证请求头使用 `header_type` 指定的认证方案关键字，其默认值为 `ldap` 而非 `basic`，即默认要求 `Authorization: ldap <base64(username:password)>`。如需使用标准的 [basic authentication](https://en.wikipedia.org/wiki/Basic_access_authentication)，请将 `header_type` 设置为 `basic`。

插件会区分以下三种失败场景，因此服务端故障不会被误判为凭证错误：

| 状态码 | 原因 |
|--------|------|
| `401` | 凭证缺失、格式错误或被拒绝；用户名匹配到多个条目；或 `consumer_required` 为 `true` 但没有匹配的 Consumer。响应中会携带 `WWW-Authenticate` 请求头。 |
| `403` | 用户认证成功，但不满足 `groups_required`。 |
| `500` | LDAP 服务器不可达、`bind_dn` 凭证被拒绝，或用户组搜索失败。 |

该插件使用 [lua-resty-ldap](https://github.com/api7/lua-resty-ldap) 连接 LDAP 服务器。

## 属性

Consumer 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| user_dn | string | 否 | | | 与该 Consumer 绑定的 LDAP 用户 DN，例如 `cn=Jane Doe,ou=users,dc=example,dc=org`。与 `group_dn` 互斥，两者必须且只能配置其一。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源保存在密钥管理服务中。 |
| group_dn | string 或 array[string] | 否 | | | 用户组 DN，或用户必须**同时**属于的多个用户组 DN，例如 `cn=ops,ou=groups,dc=example,dc=org`。与 `user_dn` 互斥，两者必须且只能配置其一。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源保存在密钥管理服务中。 |

Route 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| ldap_uri | string | 是 | | | LDAP 服务器地址，格式为 `host` 或 `host:port`。省略端口时，启用 `use_ldaps` 使用 `636`，否则使用 `389`。 |
| base_dn | string | 是 | | | 搜索用户的子树 DN，例如 `ou=users,dc=example,dc=org`。 |
| attribute | string | 否 | cn | | 与请求中用户名匹配的用户属性，例如 `uid` 或 `sAMAccountName`。 |
| bind_dn | string | 否 | | | 搜索用户前用于绑定的 DN。未配置时使用匿名绑定进行搜索。 |
| ldap_password | string | 否 | | | `bind_dn` 对应的密码。配置 `bind_dn` 时必填。该密码在存入 etcd 前使用 AES 加密。 |
| use_ldaps | boolean | 否 | false | | 如果为 true，则使用 LDAPS 连接。与 `use_starttls` 互斥。 |
| use_starttls | boolean | 否 | false | | 如果为 true，则通过 StartTLS 升级明文连接。与 `use_ldaps` 互斥。 |
| ssl_verify | boolean | 否 | true | | 如果为 true，则校验 LDAP 服务器证书。此时需要在 `config.yaml` 中配置 `ssl_trusted_certificate`，并确保 `ldap_uri` 中的主机名与服务器证书中的主机名一致。 |
| timeout | integer | 否 | 10000 | [1, 60000] | 套接字超时时间，单位为毫秒。 |
| keepalive | boolean | 否 | true | | 如果为 true，则将连接放回连接池复用，而不是直接关闭。 |
| keepalive_timeout | integer | 否 | 60000 | >= 1000 | 连接池中连接的空闲超时时间，单位为毫秒。 |
| keepalive_pool_size | integer | 否 | 5 | >= 1 | 连接池中保持的最大连接数。 |
| keepalive_pool_name | string | 否 | | | 连接池名称。当不同配置使用不同凭证时，可通过该字段将连接隔离到不同的连接池。 |
| size_limit | integer | 否 | 2 | >= 2 | 用户搜索返回条目数的上限。登录属性应当唯一，因此匹配到多个条目会被视为歧义并拒绝。 |
| time_limit | integer | 否 | 5 | >= 0 | 搜索的时间限制，单位为秒。`0` 表示使用服务器默认值。 |
| group_base_dn | string | 否 | | | 搜索用户组的子树 DN。配置后，插件会在该子树中搜索 `group_member_attribute` 包含用户 DN 的条目。未配置时，则直接从用户条目的 `user_membership_attribute` 属性读取用户组，无需额外的请求往返。 |
| group_name_attribute | string | 否 | cn | | 作为用户组名称的用户组属性。仅可与 `group_base_dn` 一起使用。 |
| group_member_attribute | string | 否 | member | | 记录成员 DN 的用户组属性。仅可与 `group_base_dn` 一起使用。 |
| user_membership_attribute | string | 否 | memberOf | | 记录用户所属用户组 DN 的用户属性。在未配置 `group_base_dn` 时使用。 |
| groups_required | array[array[string]] | 否 | | | 用户必须满足的用户组条件。外层数组为逻辑“或”，每个内层数组为逻辑“与”。例如 `[["a","b"],["c"]]` 允许同时属于 `a` 与 `b` 的用户，也允许属于 `c` 的用户。名称按大小写敏感的方式精确匹配。 |
| consumer_required | boolean | 否 | true | | 如果为 true，当没有 Consumer 与认证用户匹配时，返回 `401` 拒绝请求。 |
| header_type | string | 否 | ldap | ["ldap", "basic"] | 凭证请求头中期望的认证方案关键字。 |
| realm | string | 否 | ldap | | 认证失败返回 `401 Unauthorized` 时，[`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) 响应头中的 realm 值。 |
| set_groups_header | boolean | 否 | true | | 如果为 true，则将收集到的用户组名称以逗号分隔添加到请求的 `X-Authenticated-Groups` 请求头中。无论插件是否设置该请求头，客户端传入的该请求头都会被移除。 |

## 示例

以下示例假设 LDAP 目录位于 `dc=example,dc=org` 下，其中用户 `Jane Doe` 的 `uid` 为 `jdoe`、密码为 `janesecret`，属于 `Domain Admins` 与 `ops` 用户组；用户 `user01` 的密码为 `password1`，属于 `Domain Admins` 与 `developers` 用户组。

:::note

您可以通过以下命令从 `config.yaml` 中获取 `admin_key`，并将其保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用 LDAP 目录进行身份认证

以下示例展示了最小配置：在 `base_dn` 中搜索 `uid` 匹配的用户，然后以该用户进行绑定。

创建路由并启用 `ldap-auth-advanced` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "127.0.0.1:1389",
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid",
        "consumer_required": false
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

使用正确的凭证发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

您将会收到 `HTTP/1.1 200 OK` 响应。

不携带凭证发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您将会收到 `HTTP/1.1 401 Unauthorized` 响应，响应体如下：

```text
{"message":"Authorization required"}
```

响应中同时会携带由 `realm` 生成的认证质询：

```text
WWW-Authenticate: ldap realm="ldap"
```

密码错误的请求也会以同样的方式被拒绝。

如果目录不允许匿名搜索，可以添加 `bind_dn` 与 `ldap_password` 使用服务账号进行绑定。用户本身仍然通过自己的绑定完成认证：

```json
{
  "ldap-auth-advanced": {
    "ldap_uri": "127.0.0.1:1389",
    "base_dn": "ou=users,dc=example,dc=org",
    "attribute": "uid",
    "bind_dn": "cn=admin,dc=example,dc=org",
    "ldap_password": "adminpassword",
    "consumer_required": false
  }
}
```

如需使用标准的 basic authentication 而非 `ldap` 方案，请将 `header_type` 设置为 `basic`，此后客户端即可使用 `curl -u jdoe:janesecret` 发送请求。

### 将 LDAP 用户组传递给上游服务

插件默认从用户条目的 `memberOf` 属性读取用户组，并通过 `X-Authenticated-Groups` 请求头转发给上游服务，使上游服务无需查询目录即可实现自己的鉴权逻辑。

使用上一个示例中的路由发送认证请求：

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

您将在响应中看到该请求头：

```json
{
  "headers": {
    "Authorization": "ldap amRvZTpqYW5lc2VjcmV0",
    "X-Authenticated-Groups": "Domain Admins,ops",
    ...
  },
  ...
}
```

将 `set_groups_header` 设置为 `false` 可以不添加该请求头。

对于不维护 `memberOf` 属性的目录，成员关系记录在用户组条目上。此时可以配置 `group_base_dn`，在该子树中搜索包含该用户的用户组：

```json
{
  "ldap-auth-advanced": {
    "ldap_uri": "127.0.0.1:1389",
    "base_dn": "ou=users,dc=example,dc=org",
    "attribute": "uid",
    "group_base_dn": "ou=groups,dc=example,dc=org",
    "group_member_attribute": "member",
    "group_name_attribute": "cn",
    "consumer_required": false
  }
}
```

两种方式得到的用户组名称相同，但名称的顺序不作保证。

### 基于 LDAP 用户组限制访问

配置 `groups_required` 后，只有满足指定用户组组合的用户才能访问。外层数组为逻辑“或”，每个内层数组为逻辑“与”。

更新路由，允许同时属于 `Domain Admins` 与 `ops` 的用户，以及属于 `superadmin` 的用户访问：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "127.0.0.1:1389",
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid",
        "groups_required": [["Domain Admins", "ops"], ["superadmin"]],
        "consumer_required": false
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

`jdoe` 同时属于第一个条件中的两个用户组：

```shell
curl -i "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

您将会收到 `HTTP/1.1 200 OK` 响应。

`user01` 可以通过认证，但其属于 `developers` 而非 `ops`，两个条件均不满足：

```shell
curl -i "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'user01:password1' | base64)"
```

您将会收到 `HTTP/1.1 403 Forbidden` 响应，响应体如下：

```text
{"message":"Forbidden"}
```

### 将 LDAP 身份映射到 Consumer

将 LDAP 身份与 Consumer 关联后，APISIX 可以应用针对该 Consumer 的配置（例如限流），并在转发给上游的请求中添加 `X-Consumer-Username` 请求头。Consumer 既可以通过 `user_dn` 绑定到单个用户，也可以通过 `group_dn` 绑定到某个用户组。

创建绑定到单个用户的 Consumer：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane",
    "plugins": {
      "ldap-auth-advanced": {
        "user_dn": "cn=Jane Doe,ou=users,dc=example,dc=org"
      }
    }
  }'
```

创建绑定到某个用户组全体成员的 Consumer：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "opsteam",
    "plugins": {
      "ldap-auth-advanced": {
        "group_dn": "cn=ops,ou=groups,dc=example,dc=org"
      }
    }
  }'
```

更新路由，移除 `consumer_required` 使其恢复默认值 `true`，从而要求匹配 Consumer：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "127.0.0.1:1389",
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

以 `jdoe` 发送请求：

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

您将在转发给上游的请求中看到 Consumer 信息：

```json
{
  "headers": {
    "X-Consumer-Username": "jane",
    "X-Authenticated-Groups": "Domain Admins,ops",
    ...
  },
  ...
}
```

`jdoe` 同时也属于 `ops`，但 `user_dn` 绑定更精确，始终优先生效；`ops` 的其他成员则会匹配到 `opsteam`。未匹配到任何 Consumer 的用户会被返回 `401`，除非将 `consumer_required` 设置为 `false`。

如需要求用户同时属于多个用户组，可以将 `group_dn` 配置为数组，此时用户必须属于其中的每一个 DN：

```json
{
  "ldap-auth-advanced": {
    "group_dn": [
      "cn=Domain Admins,ou=groups,dc=example,dc=org",
      "cn=ops,ou=groups,dc=example,dc=org"
    ]
  }
}
```

当有多个 `group_dn` Consumer 同时满足条件时，插件会做出确定性的选择，并记录警告日志列出所有候选 Consumer。建议在配置时避免用户组 Consumer 之间出现重叠。

### 通过 LDAPS 连接

配置 `use_ldaps` 可以使用 LDAPS 连接，配置 `use_starttls` 则可以通过 StartTLS 升级明文连接。两者互斥，同时启用时配置会被拒绝。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "ldap.example.org",
        "use_ldaps": true,
        "ssl_verify": true,
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid",
        "consumer_required": false
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

`ldap_uri` 省略端口时，启用 `use_ldaps` 使用 `636`，否则使用 `389`。

`ssl_verify` 默认开启。此时需要在 `config.yaml` 中通过 `ssl_trusted_certificate` 配置签发 LDAP 服务器证书的 CA 证书，并确保 `ldap_uri` 中的主机名与证书一致。证书校验失败的请求会返回 `500`。

## 删除插件

当您需要禁用 `ldap-auth-advanced` 插件时，可以将对应的 JSON 配置从插件配置中删除，APISIX 将会自动重新加载，无需重启服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/ldap-auth-advanced-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {}
  }'
```
