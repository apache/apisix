---
title: Admin API
keywords:
  - APISIX
  - API 网关
  - Admin API
  - 路由
  - 插件
  - 上游
description: 本文介绍了 Apache APISIX Admin API 支持的功能，你可以通过 Admin API 来获取、创建、更新以及删除资源。
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

## 描述 {#description}

Admin API 是一组用于配置 Apache APISIX 路由、上游、服务、SSL 证书等功能的 RESTful API。

你可以通过 Admin API 来获取、创建、更新以及删除资源。同时得益于 APISIX 的热加载能力，资源配置完成后 APISIX 将会自动更新配置，无需重启服务。如果你想要了解其工作原理，请参考 [Architecture Design](./architecture-design/apisix.md)。

## 相关配置 {#basic-configuration}

当 APISIX 启动时，Admin API 默认情况下将会监听 `9180` 端口，并且会占用前缀为 `/apisix/admin` 的 API。

因此，为了避免你设计的 API 与 `/apisix/admin` 冲突，你可以通过修改配置文件 [`/conf/config.yaml`](https://github.com/apache/apisix/blob/master/conf/config.yaml) 中的配置修改默认监听端口。

APISIX 支持设置 Admin API 的 IP 访问白名单，防止 APISIX 被非法访问和攻击。你可以在 `./conf/config.yaml` 文件中的 `deployment.admin.allow_admin` 选项中，配置允许访问的 IP 地址。

在下文出现的 `X-API-KEY` 指的是 `./conf/config.yaml` 文件中的 `deployment.admin.admin_key.key`，它是 Admin API 的访问 token。

:::tip 提示

建议你修改 Admin API 默认的监听端口、IP 访问白名单以及 Admin API 的 token，以保证你的 API 安全。

:::

```yaml title="./conf/config.yaml"
deployment:
    admin:
        admin_key:
        - name: admin
            key: edd1c9f034335f136f87ad84b625c8f1  # 使用默认的 Admin API Key 存在安全风险，部署到生产环境时请及时更新
            role: admin
        allow_admin:                    # http://nginx.org/en/docs/http/ngx_http_access_module.html#allow
            - 127.0.0.0/24
        admin_listen:
            ip: 0.0.0.0                 # Admin API 监听的 IP，如果不设置，默认为“0.0.0.0”。
            port: 9180                  # Admin API 监听的 端口，必须使用与 node_listen 不同的端口。
```

### 使用环境变量 {#using-environment-variables}

要通过环境变量进行配置，可以使用 `${{VAR}}` 语法。例如：

```yaml title="./conf/config.yaml"
deployment:
  admin:
    admin_key:
    - name: admin
      key: ${{ADMIN_KEY}}
      role: admin
    allow_admin:
    - 127.0.0.0/24
    admin_listen:
      ip: 0.0.0.0
      port: 9180
```

然后在 `make init` 之前运行 `export ADMIN_KEY=$your_admin_key`.

如果找不到配置的环境变量，将抛出错误。

此外，如果要在未设置环境变量时使用默认值，请改用 `${{VAR:=default_value}}`。例如：

```yaml title="./conf/config.yaml"
deployment:
  admin:
    admin_key:
    - name: admin
      key: ${{ADMIN_KEY:=edd1c9f034335f136f87ad84b625c8f1}}
      role: admin
    allow_admin:
    - 127.0.0.0/24
    admin_listen:
      ip: 0.0.0.0
      port: 9180
```

首先查找环境变量 `ADMIN_KEY`，如果该环境变量不存在，它将使用 `edd1c9f034335f136f87ad84b625c8f1` 作为默认值。

您还可以在 yaml 键中指定环境变量。这在 `standalone` 模式 中特别有用，您可以在其中指定上游节点，如下所示：

```yaml title="./conf/apisix.yaml"
routes:
  -
    uri: "/test"
    upstream:
      nodes:
        "${{HOST_IP}}:${{PORT}}": 1
      type: roundrobin
#END
```

### 强制删除 {#force-delete}

默认情况下，Admin API 会检查资源间的引用关系，将会拒绝删除正在使用中的资源。

可以通过在删除请求中添加请求参数 `force=true` 来进行强制删除，例如：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
$ curl http://127.0.0.1:9180/apisix/admin/upstreams/1 -H "X-API-KEY: $admin_key" -X PUT -d '{
    "nodes": {
        "127.0.0.1:8080": 1
    },
    "type": "roundrobin"
}'
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '{
    "uri": "/*",
    "upstream_id": 1
}'
{"value":{"priority":0,"upstream_id":1,"uri":"/*","create_time":1689038794,"id":"1","status":1,"update_time":1689038916},"key":"/apisix/routes/1"}

$ curl http://127.0.0.1:9180/apisix/admin/upstreams/1 -H "X-API-KEY: $admin_key" -X DELETE
{"error_msg":"can not delete this upstream, route [1] is still using it now"}
$ curl "http://127.0.0.1:9180/apisix/admin/upstreams/1?force=anyvalue" -H "X-API-KEY: $admin_key" -X DELETE
{"error_msg":"can not delete this upstream, route [1] is still using it now"}
$ curl "http://127.0.0.1:9180/apisix/admin/upstreams/1?force=true" -H "X-API-KEY: $admin_key" -X DELETE
{"deleted":"1","key":"/apisix/upstreams/1"}
```

## v3 版本新功能 {#v3-new-function}

在 APISIX v3 版本中，Admin API 支持了一些不向下兼容的新特性，比如支持新的响应体格式、支持分页查询、支持过滤资源等。

### 支持新的响应体格式 {#support-new-response-body-format}

APISIX 在 v3 版本对响应体做了以下调整：

- 移除旧版本响应体中的 `action` 字段；
- 调整获取资源列表时的响应体结构，新的响应体结构示例如下：

返回单个资源：

```json
    {
    "modifiedIndex": 2685183,
    "value": {
        "id": "1",
        ...
    },
    "key": "/apisix/routes/1",
    "createdIndex": 2684956
    }
```

返回多个资源：

```json
    {
    "list": [
        {
        "modifiedIndex": 2685183,
        "value": {
            "id": "1",
            ...
        },
        "key": "/apisix/routes/1",
        "createdIndex": 2684956
        },
        {
        "modifiedIndex": 2685163,
        "value": {
            "id": "2",
            ...
        },
        "key": "/apisix/routes/2",
        "createdIndex": 2685163
        }
    ],
    "total": 2
    }
```

### 支持分页查询 {#support-paging-query}

获取资源列表时支持分页查询，目前支持分页查询的资源如下：

- [Consumer](#consumer)
- [Consumer Group](#consumer-group)
- [Global Rules](#global-rules)
- [Plugin Config](#plugin-config)
- [Protos](https://apisix.apache.org/zh/docs/apisix/plugins/grpc-transcode/#%E5%90%AF%E7%94%A8%E6%8F%92%E4%BB%B6)
- [Route](#route)
- [Service](#service)
- [SSL](#ssl)
- [Stream Route](#stream-route)
- [Upstream](#upstream)

参数如下：

| 名称       | 默认值 | 范围     | 描述                                                |
| --------- | ------ | -------- | -------------------------------------------------- |
| page      | 1      | [1, ...] | 页数，默认展示第一页。                               |
| page_size |        | [10, 500]| 每页资源数量。如果不配置该参数，则展示所有查询到的资源。|

示例如下：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes?page=1&page_size=10" \
-H "X-API-KEY: $admin_key" -X GET
```

```json
{
  "total": 1,
  "list": [
    {
      ...
    }
  ]
}
```

### 支持过滤资源 {#support-filtering-query}

在 APISIX v3 版本中，在获取资源列表时，你可以使用 `name`、`label` 和 `uri` 参数过滤资源。支持参数如下：

| 名称   | 描述                                                                                                                      |
| ----- | ------------------------------------------------------------------------------------------------------------------------ |
| name  | 根据资源的 `name` 属性进行查询，如果资源本身没有 `name` 属性则不会出现在查询结果中。                                           |
| label | 根据资源的 `label` 属性进行查询，如果资源本身没有 `label` 属性则不会出现在查询结果中。                                         |
| uri   | 该参数仅在 Route 资源上支持。如果 Route 的 `uri` 等于查询的 `uri` 或 `uris` 包含查询的 `uri`，则该 Route 资源出现在查询结果中。 |

:::tip 提示

当使用多个过滤参数时，APISIX 将对不同过滤参数的查询结果取交集。

:::

以下示例将返回一个路由列表，该路由列表中的所有路由需要满足以下条件：路由的 `name` 包含字符串 `test`；`uri` 包含字符串 `foo`；对路由的 `label` 没有限制，因为 `label` 为空字符串。

```shell
curl 'http://127.0.0.1:9180/apisix/admin/routes?name=test&uri=foo&label=' \
-H "X-API-KEY: $admin_key" -X GET
```

返回结果：

```json
{
  "total": 1,
  "list": [
    {
      ...
    }
  ]
}
```

### 支持引用过滤资源 {#support-reference-filtering-query}

:::note

这个特性于 APISIX 3.13.0 引入。

APISIX 支持通过 `service_id` 和 `upstream_id` 查询路由和 Stream 路由。现在不支持其他资源或字段。

:::

在获取资源列表时，你可以使用 `filter` 参数过滤资源。

它以以下方式编码：

```text
filter=escape_uri(key1=value1&key2=value2)
```

以下是一个使用 `service_id` 进行路由列表过滤的例子。当同时设置了多个过滤条件，结果将为它们的交集。

```shell
curl 'http://127.0.0.1:9180/apisix/admin/routes?filter=service_id%3D1' \
-H "X-API-KEY: $admin_key" -X GET
```

```json
{
  "total": 1,
  "list": [
    {
      ...
    }
  ]
}
```

## Route

Route 也称之为路由，可以通过定义一些规则来匹配客户端的请求，然后根据匹配结果加载并执行相应的插件，并把请求转发给到指定 Upstream（上游）。

### 请求地址 {#route-uri}

路由资源请求地址：/apisix/admin/routes/{id}?ttl=0

### 请求方法 {#route-request-methods}

| 名称   | 请求 URI                          | 请求 body  | 描述                                                                                                 |
| ------ | -------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/routes             | 无        | 获取资源列表。                                                                                                                              |
| GET    | /apisix/admin/routes/{id}        | 无        | 获取资源。                                                                                                                                         |
| PUT    | /apisix/admin/routes/{id}        | {...}     | 根据 id 创建资源。                                                                                                                        |
| POST   | /apisix/admin/routes             | {...}     | 创建资源，id 将会自动生成。                                                                                                                      |
| DELETE | /apisix/admin/routes/{id}        | 无        | 删除指定资源。                                                                                                                                                |
| PATCH  | /apisix/admin/routes/{id}        | {...}     | 标准 PATCH，修改指定 Route 的部分属性，其他不涉及的属性会原样保留；如果你需要删除某个属性，可以将该属性的值设置为 `null`；当需要修改属性的值为数组时，该属性将全量更新。 |
| PATCH  | /apisix/admin/routes/{id}/{path} | {...}     | SubPath PATCH，通过 `{path}` 指定 Route 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。两种 PATCH 的区别，请参考使用示例。                         |

### URI 请求参数 {#route-uri-request-parameters}

| 名称 | 必选项  | 类型  | 描述                                         | 示例  |
| ---- | ------ | ---- | -------------------------------------------- | ----- |
| ttl  | 否     | 辅助 | 路由的有效期。超过定义的时间，APISIX 将会自动删除路由，单位为秒。  | ttl=1 |

### body 请求参数 {#route-request-body-parameters}

| 名称             | 必选项                            | 类型     | 描述                                                                                                                                                                                                                                                                                    | 示例值                                                 |
| ---------------- | -------------------------------- | -------- |---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| ---------------------------------------------------- |
| uri              | 是，与 `uris` 二选一。       | 匹配规则 | 除了如 `/foo/bar`、`/foo/gloo` 这种全量匹配外，使用不同 [Router](terminology/router.md) 还允许更高级匹配，更多信息请参考 [Router](terminology/router.md)。                                                                                                                                                 | "/hello"                                             |
| uris             | 是，不能与 `uri` 二选一。        | 匹配规则 | 非空数组形式，可以匹配多个 `uri`。                                                                                                                                                                                                                                                               | ["/hello", "/world"]                                 |
| plugins          | 否                               | Plugin   | Plugin 配置，请参考 [Plugin](terminology/plugin.md)。                                                                                                                                                                                                                                            |                                                      |
| script           | 否                               | Script   | Script 配置，请参考 [Script](terminology/script.md)。                                                                                                                                                                                                                                            |                                                      |
| upstream         | 否                               | Upstream | Upstream 配置，请参考 [Upstream](terminology/upstream.md)。                                                                                                                                                                                                                              |                                                      |
| upstream_id      | 否                               | Upstream | 需要使用的 Upstream id，请参考 [Upstream](terminology/upstream.md)。                                                                                                                                                                                                                     |                                                      |
| service_id       | 否                               | Service  | 需要绑定的 Service id，请参考 [Service](terminology/service.md)。                                                                                                                                                                                                                        |                                                      |
| plugin_config_id | 否，不能与 Script 共同使用。      | Plugin   | 需要绑定的 Plugin Config id，请参考 [Plugin Config](terminology/plugin-config.md)。                                                                                                                                                                                                           |                                                      |
| name             | 否                               | 辅助     | 路由名称。                                                                                                                                                                                                                                                                                | route-test                                          |
| desc             | 否                               | 辅助     | 路由描述信息。                                                                                                                                                                                                                                                                     | 用来测试的路由。                                            |
| host             | 否，与 `hosts` 二选一。      | 匹配规则 | 当前请求域名，比如 `foo.com`；也支持泛域名，比如 `*.foo.com`。                                                                                                                                                                                                                                            | "foo.com"                                            |
| hosts            | 否，与 `host` 二选一。       | 匹配规则 | 非空列表形态的 `host`，表示允许有多个不同 `host`，匹配其中任意一个即可。                                                                                                                                                                                                                                           | ["foo.com", "\*.bar.com"]                            |
| remote_addr      | 否，与 `remote_addrs` 二选一。| 匹配规则 | 客户端请求的 IP 地址。支持 IPv4 地址，如：`192.168.1.101` 以及 CIDR 格式的支持 `192.168.1.0/24`；支持 IPv6 地址匹配，如 `::1`，`fe80::1`，`fe80::1/64` 等。                                                                                                                                                 | "192.168.1.0/24"                                     |
| remote_addrs     | 否，与 `remote_addr` 二选一。| 匹配规则 | 非空列表形态的 `remote_addr`，表示允许有多个不同 IP 地址，符合其中任意一个即可。                                                                                                                                                                                                                                     | ["127.0.0.1", "192.0.0.0/8", "::1"]                  |
| methods          | 否                               | 匹配规则 | 如果为空或没有该选项，则表示没有任何 `method` 限制。你也可以配置一个或多个的组合：`GET`，`POST`，`PUT`，`DELETE`，`PATCH`，`HEAD`，`OPTIONS`，`CONNECT`，`TRACE`，`PURGE`。                                                                                                                                                                    | ["GET", "POST"]                                      |
| priority         | 否                               | 匹配规则 | 如果不同路由包含相同的 `uri`，则根据属性 `priority` 确定哪个 `route` 被优先匹配，值越大优先级越高，默认值为 `0`。                                                                                                                                                                                                                  | priority = 10                                        |
| vars             | 否                               | 匹配规则 | 由一个或多个`[var, operator, val]`元素组成的列表，类似 `[[var, operator, val], [var, operator, val], ...]]`。例如：`["arg_name", "==", "json"]` 则表示当前请求参数 `name` 是 `json`。此处 `var` 与 NGINX 内部自身变量命名是保持一致的，所以也可以使用 `request_uri`、`host` 等。更多细节请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 | [["arg_name", "==", "json"], ["arg_age", ">", 18]]   |
| filter_func      | 否                               | 匹配规则 | 用户自定义的过滤函数。可以使用它来实现特殊场景的匹配要求实现。该函数默认接受一个名为 `vars` 的输入参数，可以用它来获取 NGINX 变量。                                                                                                                                                                                                               | function(vars) return vars["arg_name"] == "json" end |
| labels           | 否                               | 匹配规则 | 标识附加属性的键值对。                                                                                                                                                                                                                                                                            | {"version":"v2","build":"16","env":"production"}     |
| timeout          | 否                               | 辅助     | 为 Route 设置 Upstream 连接、发送消息和接收消息的超时时间（单位为秒）。该配置将会覆盖在 Upstream 中配置的 [timeout](#upstream) 选项。                                                                                                                                                                                               | {"connect": 3, "send": 3, "read": 3}              |
| enable_websocket | 否                               | 辅助     | 当设置为 `true` 时，启用 `websocket`(boolean), 默认值为 `false`。                                                                                                                                                                                                                                                |                                                      |
| status           | 否                               | 辅助     | 当设置为 `1` 时，启用该路由，默认值为 `1`。                                                                                                                                                                                                                                                                       | `1` 表示启用，`0` 表示禁用。                           |

:::note 注意

- 对于同一类参数比如 `uri`与 `uris`，`upstream` 与 `upstream_id`，`host` 与 `hosts`，`remote_addr` 与 `remote_addrs` 等，是不能同时存在，二者只能选择其一。如果同时启用，则会出现异常。
- 在 `vars` 中，当获取 Cookie 的值时，Cookie name 是**区分大小写字母**的。例如：`var = cookie_x_foo` 与 `var  = cookie_X_Foo` 表示不同的 `cookie`。

:::

Route 对象 JSON 配置示例：

```shell
{
    "id": "1",                            # id，非必填
    "uris": ["/a","/b"],                  # 一组 URL 路径
    "methods": ["GET","POST"],            # 可以填多个方法
    "hosts": ["a.com","b.com"],           # 一组 host 域名
    "plugins": {},                        # 指定 route 绑定的插件
    "priority": 0,                        # apisix 支持多种匹配方式，可能会在一次匹配中同时匹配到多条路由，此时优先级高的优先匹配中
    "name": "路由 xxx",
    "desc": "hello world",
    "remote_addrs": ["127.0.0.1"],        # 一组客户端请求 IP 地址
    "vars": [["http_user", "==", "ios"]], # 由一个或多个 [var, operator, val] 元素组成的列表
    "upstream_id": "1",                   # upstream 对象在 etcd 中的 id，建议使用此值
    "upstream": {},                       # upstream 信息对象，建议尽量不要使用
    "timeout": {                          # 为 route 设置 upstream 的连接、发送消息、接收消息的超时时间。
        "connect": 3,
        "send": 3,
        "read": 3
    },
    "filter_func": ""                     # 用户自定义的过滤函数，非必填
}
```

### 使用示例 {#route-example}

- 创建一个路由：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "uri": "/index.html",
        "hosts": ["foo.com", "*.bar.com"],
        "remote_addrs": ["127.0.0.0/8"],
        "methods": ["PUT", "GET"],
        "enable_websocket": true,
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

    ```
    HTTP/1.1 201 Created
    Date: Sat, 31 Aug 2019 01:17:15 GMT
    ...
    ```

- 创建一个有效期为 60 秒的路由，过期后自动删除：

    ```shell
    curl 'http://127.0.0.1:9180/apisix/admin/routes/2?ttl=60' \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "uri": "/aa/index.html",
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

    ```
    HTTP/1.1 201 Created
    Date: Sat, 31 Aug 2019 01:17:15 GMT
    ...
    ```

- 在路由中新增一个上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点将更新为：

    ```
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

- 更新路由中上游节点的权重：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 10
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点将更新为：

    ```
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

- 从路由中删除一个上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": null
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，Upstream `nodes` 将更新为：

    ```shell
    {
        "127.0.0.1:1981": 10
    }
    ```

- 更新路由中的 `methods` 数组

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '{
        "methods": ["GET", "POST"]
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`methods` 将不保留原来的数据，将更新为：

    ```
    ["GET", "POST"]
    ```

- 使用 `sub path` 更新路由中的上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1/upstream/nodes \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`nodes` 将不保留原来的数据，整个更新为：

    ```
    {
        "127.0.0.1:1982": 1
    }
    ```

- 使用 `sub path` 更新路由中的 `methods`：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1/methods \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '["POST", "DELETE", "PATCH"]'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`methods` 将不保留原来的数据，更新为：

    ```
    ["POST", "DELETE", "PATCH"]
    ```

- 禁用路由

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "status": 0
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`status` 将更新为：

    ```
    {
        "status": 0
    }
    ```

- 启用路由

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "status": 1
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`status` 将更新为：

    ```
    {
        "status": 1
    }
    ```

### 应答参数 {#route-response-parameters}

目前是直接返回与 etcd 交互后的结果。

## Service

Service 是某类 API 的抽象（也可以理解为一组 Route 的抽象）。它通常与上游服务抽象是一一对应的，`Route` 与 `Service` 之间，通常是 N:1 的关系。

### 请求地址 {#service-uri}

服务资源请求地址：/apisix/admin/services/{id}

### 请求方法  {#service-request-methods}

| 名称   | 请求 URI                          | 请求 body | 描述                                                                                                                                                               |
| ------ | ---------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/services             | 无        | 获取资源列表。                                                                                                                                                      |
| GET    | /apisix/admin/services/{id}        | 无        | 获取资源。                                                                                                                                                         |
| PUT    | /apisix/admin/services/{id}        | {...}     | 创建指定 id 资源。                                                                                                                                                  |
| POST   | /apisix/admin/services             | {...}     | 创建资源，id 由后台服务自动生成。                                                                                                                                    |
| DELETE | /apisix/admin/services/{id}        | 无        | 删除资源。                                                                                                                                                          |
| PATCH  | /apisix/admin/services/{id}        | {...}     | 标准 PATCH，修改已有 Service 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为 null 即可删除；**注意**：当需要修改属性的值为数组时，该属性将全量更新。|
| PATCH  | /apisix/admin/services/{id}/{path} | {...}     | SubPath PATCH，通过 {path} 指定 Service 需要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                                                                |

### body 请求参数 {#service-request-body-parameters}

| 名称             | 必选项                   | 类型     | 描述                                                             | 示例                                             |
| ---------------- | ----------------------- | -------- | ---------------------------------------------------------------- | ------------------------------------------------ |
| plugins          | 否                      | Plugin   | Plugin 配置，请参考 [Plugin](terminology/plugin.md)。               |                                                  |
| upstream         | 与 `upstream_id` 二选一。  | Upstream | Upstream 配置，请参考 [Upstream](terminology/upstream.md)。         |                                                  |
| upstream_id      | 与 `upstream` 二选一。    | Upstream | 需要使用的 upstream id，请参考 [Upstream](terminology/upstream.md)。|                                                  |
| name             | 否                     | 辅助     | 服务名称。                                                      |                                             |
| desc             | 否                     | 辅助     | 服务描述。                                                          |                                                  |
| labels           | 否                     | 匹配规则 | 标识附加属性的键值对。                                                 | {"version":"v2","build":"16","env":"production"} |
| enable_websocket | 否                     | 辅助     | `websocket`(boolean) 配置，默认值为 `false`。                       |                                                  |
| hosts            | 否                     | 匹配规则 | 非空列表形态的 `host`，表示允许有多个不同 `host`，匹配其中任意一个即可。| ["foo.com", "\*.bar.com"]                        |

Service 对象 JSON 配置示例：

```shell
{
    "id": "1",                # id
    "plugins": {},            # 指定 service 绑定的插件
    "upstream_id": "1",       # upstream 对象在 etcd 中的 id，建议使用此值
    "upstream": {},           # upstream 信息对象，不建议使用
    "name": "test svc",       # service 名称
    "desc": "hello world",    # service 描述
    "enable_websocket": true, # 启动 websocket 功能
    "hosts": ["foo.com"]
}
```

### 使用示例 {#service-example}

- 创建一个 Service：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201  \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        },
        "enable_websocket": true,
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

    ```
    HTTP/1.1 201 Created
    ...
    ```

- 在 Service 中添加一个上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点将更新为：

    ```json
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

- 更新一个上游节点的权重：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 10
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点将更新为：

    ```
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

- 删除 Service 中的一个上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": null
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点将更新为：

    ```
    {
        "127.0.0.1:1981": 10
    }
    ```

- 替换 Service 的上游节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201/upstream/nodes \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，上游节点不再保留原来的数据，将更新为：

    ```
    {
        "127.0.0.1:1982": 1
    }
    ```

### 应答参数 {#service-response-parameters}

目前是直接返回与 etcd 交互后的结果。

## Consumer

Consumer 是某类服务的消费者，需要与用户认证体系配合才能使用。Consumer 使用 `username` 作为唯一标识，仅支持使用 HTTP `PUT` 方法创建 Consumer。

### 请求地址 {#consumer-uri}

Consumer 资源请求地址：/apisix/admin/consumers/{username}

### 请求方法 {#consumer-request-methods}

| 名称   | 请求 URI                           | 请求 body | 描述          |
| ------ | ---------------------------------- | --------- | ------------- |
| GET    | /apisix/admin/consumers            | 无        | 获取资源列表。|
| GET    | /apisix/admin/consumers/{username} | 无        | 获取资源。    |
| PUT    | /apisix/admin/consumers            | {...}     | 创建资源。    |
| DELETE | /apisix/admin/consumers/{username} | 无        | 删除资源。    |

### body 请求参数 {#consumer-body-request-methods}

| 名称        | 必选项 | 类型     | 描述                                                                                                                             | 示例值                                             |
| ----------- | ----- | ------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| username    | 是   | 辅助     | Consumer 名称。                                                                                                                  |                                                  |
| group_id    | 否   | 辅助     | Consumer Group 名称。                                                                                                            |                                                  |
| plugins     | 否   | Plugin   | 该 Consumer 对应的插件配置，它的优先级是最高的：Consumer > Route > Plugin Config > Service。对于具体插件配置，请参考 [Plugins](#plugin)。     |                                                  |
| desc        | 否   | 辅助     | consumer 描述。                                                                                                                  |                                                  |
| labels      | 否   | 匹配规则  | 标识附加属性的键值对。                                                                                                             | {"version":"v2","build":"16","env":"production"} |

Consumer 对象 JSON 配置示例：

```shell
{
    "plugins": {},          # 指定 consumer 绑定的插件
    "username": "name",     # 必填
    "desc": "hello world"   # consumer 描述
}
```

当认证插件与 Consumer 一起使用时，需要提供用户名、密码等信息；当认证插件与 Route 或 Service 绑定时，则不需要任何参数，因为此时 APISIX 是根据用户请求数据来判断用户对应的是哪个 Consumer。

:::note 注意

从 APISIX v2.2 版本开始，同一个 Consumer 可以绑定多个认证插件。

:::

### 使用示例 {#consumer-example}

- 创建 Consumer，并指定认证插件 `key-auth`，并开启指定插件 `limit-count`：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers  \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "username": "jack",
        "plugins": {
            "key-auth": {
                "key": "auth-one"
            },
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    Date: Thu, 26 Dec 2019 08:17:49 GMT
    ...

    {"key":"\/apisix\/consumers\/jack","value":{"username":"jack","update_time":1666260780,"plugins":{"limit-count":{"key_type":"var","count":2,"rejected_code":503,"show_limit_quota_header":true,"time_window":60,"key":"remote_addr","allow_degradation":false,"policy":"local"},"key-auth":{"key":"auth-one"}},"create_time":1666260780}}
    ```

### 应答参数  {#consumer-response-parameters}

目前是直接返回与 etcd 交互后的结果。

## Credential

Credential 用以存放 Consumer 的认证凭证。当需要为 Consumer 配置多个凭证时，可以使用 Credential。

### 请求地址 {#credential-uri}

Credential 资源请求地址：/apisix/admin/consumers/{username}/credentials/{credential_id}

### 请求方法 {#consumer-request-methods}

| 名称   | 请求 URI                                                         | 请求 body | 描述          |
| ------ |----------------------------------------------------------------| --------- | ------------- |
| GET    | /apisix/admin/consumers/{username}/credentials                 | 无        | 获取资源列表。|
| GET    | /apisix/admin/consumers/{username}/credentials/{credential_id} | 无        | 获取资源。    |
| PUT    | /apisix/admin/consumers/{username}/credentials/{credential_id} | {...}     | 创建资源。    |
| DELETE | /apisix/admin/consumers/{username}/credentials/{credential_id} | 无        | 删除资源。    |

### body 请求参数 {#credential-body-request-methods}

| 名称        | 必选项 | 类型     | 描述                    | 示例值                                             |
| ----------- |-----| ------- |-----------------------| ------------------------------------------------ |
| plugins     | 是   | Plugin   | 该 Credential 对应的插件配置。 |                                                  |
| name        | 否   | 辅助     | 消费者 Credential 名     | credential_primary                               |
| desc        | 否   | 辅助     | Credential 描述。        |                                                  |
| labels      | 否   | 匹配规则  | 标识附加属性的键值对。           | {"version":"v2","build":"16","env":"production"} |

Credential 对象 JSON 配置示例：

```shell
{
    "plugins": {
      "key-auth": {
        "key": "auth-one"
      }
    },
    "desc": "hello world"
}
```

### 使用示例 {#credential-example}

前提：已创建 Consumer `jack`。

创建 Credential，并启用认证插件 `key-auth`：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials/auth-one  \
-H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

```
HTTP/1.1 200 OK
Date: Thu, 26 Dec 2019 08:17:49 GMT
...

{"key":"\/apisix\/consumers\/jack\/credentials\/auth-one","value":{"update_time":1666260780,"plugins":{"key-auth":{"key":"auth-one"}},"create_time":1666260780}}
```

## Upstream

Upstream 是虚拟主机抽象，对给定的多个服务节点按照配置规则进行负载均衡。Upstream 的地址信息可以直接配置到 `Route`（或 `Service`) 上，当 Upstream 有重复时，需要用“引用”方式避免重复。

### 请求地址 {#upstream-uri}

Upstream 资源请求地址：/apisix/admin/upstreams/{id}

### 请求方法 {#upstream-request-methods}

| 名称   | 请求 URI                             | 请求 body | 描述                                                                                                                                                               |
| ------ | ----------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/upstreams/{id}        | 无        | 获取资源。                                                                                                                                                        |
| PUT    | /apisix/admin/upstreams/{id}        | {...}     | 创建指定 id 的资源。                                                                                                                                               |
| POST   | /apisix/admin/upstreams             | {...}     | 创建资源，id 由后台服务自动生成。                                                                                                                                 |
| DELETE | /apisix/admin/upstreams/{id}        | 无        | 删除资源。                                                                                                                                                        |
| PATCH  | /apisix/admin/upstreams/{id}        | {...}     | 标准 PATCH，修改已有 Upstream 的部分属性，其他不涉及的属性会原样保留；如果需要删除某个属性，可将该属性的值设置为 `null`；**注意**：当需要修改属性的值为数组时，该属性将全量更新。|
| PATCH  | /apisix/admin/upstreams/{id}/{path} | {...}     | SubPath PATCH，通过 `{path}` 指定 Upstream 需要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                                                            |

### body 请求参数 {#upstream-body-request-methods}

APISIX 的 Upstream 除了基本的负载均衡算法选择外，还支持对上游做主被动健康检查、重试等逻辑。详细信息如下：

| 名称           | 必选项                                           | 类型           | 描述                                                                                                                                                                                                                                                                                                                                                        | 示例                                             |
| -------------- |-----------------------------------------------| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| type           | 否                                             | 枚举           | 负载均衡算法，默认值是`roundrobin`。                                                                                                                                                                                                                                                                                                                                                           |                                      |     |
| nodes          | 是，与 `service_name` 二选一。                       | Node           | 哈希表或数组。当它是哈希表时，内部元素的 key 是上游机器地址列表，格式为`地址 +（可选的）端口`，其中地址部分可以是 IP 也可以是域名，比如 `192.168.1.100:80`、`foo.com:80`等。对于哈希表的情况，如果 key 是 IPv6 地址加端口，则必须用中括号将 IPv6 地址括起来。`value` 则是节点的权重。当它是数组时，数组中每个元素都是一个哈希表，其中包含 `host`、`weight` 以及可选的 `port`、`priority`。`nodes` 可以为空，这通常用作占位符。客户端命中这样的上游会返回 `502`。                                        | `192.168.1.100:80`, `[::1]:80`                               |
| service_name   | 是，与 `nodes` 二选一。                              | string         | 服务发现时使用的服务名，请参考 [集成服务发现注册中心](./discovery.md)。                                                                                                                                                                                                                                                                                            | `a-bootiful-client`                              |
| discovery_type | 是，与 `service_name` 配合使用。                      | string         | 服务发现类型，请参考 [集成服务发现注册中心](./discovery.md)。                                                                                                                                                                                                                                                                                                      | `eureka`                                         |
| key            | 条件必需                                          | 匹配类型       | 该选项只有类型是 `chash` 才有效。根据 `key` 来查找对应的节点 `id`，相同的 `key` 在同一个对象中，则返回相同 id。目前支持的 NGINX 内置变量有 `uri, server_name, server_addr, request_uri, remote_port, remote_addr, query_string, host, hostname, arg_***`，其中 `arg_***` 是来自 URL 的请求参数，详细信息请参考 [NGINX 变量列表](http://nginx.org/en/docs/varindex.html)。 |                                                  |
| checks         | 否                                             | health_checker | 配置健康检查的参数，详细信息请参考 [health-check](./tutorials/health-check.md)。                                                                                                                                                                                                                                                                                               |                                                  |
| retries        | 否                                             | 整型           | 使用 NGINX 重试机制将请求传递给下一个上游，默认启用重试机制且次数为后端可用的节点数量。如果指定了具体重试次数，它将覆盖默认值。当设置为 `0` 时，表示不启用重试机制。                                                                                                                                                                                                 |                                                  |
| retry_timeout  | 否                                             | number         | 限制是否继续重试的时间，若之前的请求和重试请求花费太多时间就不再继续重试。当设置为 `0` 时，表示不启用重试超时机制。                                                                                                                                                                                                 |                                                  |
| timeout        | 否                                             | 超时时间对象   | 设置连接、发送消息、接收消息的超时时间，以秒为单位。| `{"connect": 0.5,"send": 0.5,"read": 0.5}` |
| hash_on        | 否                                             | 辅助           | `hash_on` 支持的类型有 `vars`（NGINX 内置变量），`header`（自定义 header），`cookie`，`consumer`，默认值为 `vars`。                                                                                                                                                                                                                                           |
| name           | 否                                             | 辅助           | 标识上游服务名称、使用场景等。                                                                                                                                                                                                                                                                                                                              |                                                  |
| desc           | 否                                             | 辅助           | 上游服务描述、使用场景等。                                                                                                                                                                                                                                                                                                                                  |                                                  |
| pass_host      | 否                                             | 枚举           | 请求发给上游时的 `host` 设置选型。 [`pass`，`node`，`rewrite`] 之一，默认是 `pass`。`pass`: 将客户端的 host 透传给上游； `node`: 使用 `upstream` node 中配置的 `host`； `rewrite`: 使用配置项 `upstream_host` 的值。                                                                                                                                                                        |                                                  |
| upstream_host  | 否                                             | 辅助           | 指定上游请求的 host，只在 `pass_host` 配置为 `rewrite` 时有效。                                                                                                                                                                                                                                                                                                                  |                                                  |
| scheme         | 否                                             | 辅助           | 跟上游通信时使用的 scheme。对于 7 层代理，可选值为 [`http`, `https`, `grpc`, `grpcs`]。对于 4 层代理，可选值为 [`tcp`, `udp`, `tls`]。默认值为 `http`，详细信息请参考下文。                                                                                                                                                                                                                                                           |
| labels         | 否                                             | 匹配规则       | 标识附加属性的键值对。                                                                                                                                                                                                                                                                                                                                        | {"version":"v2","build":"16","env":"production"} |
| tls.client_cert    | 否，不能和 `tls.client_cert_id` 一起使用               | https 证书           | 设置跟上游通信时的客户端证书，详细信息请参考下文。                                                                        | |
| tls.client_key	 | 否，不能和 `tls.client_cert_id` 一起使用               | https 证书私钥           | 设置跟上游通信时的客户端私钥，详细信息请参考下文。                                                                                                                                                                                                                                                                                                              | |
| tls.client_cert_id | 否，不能和 `tls.client_cert`、`tls.client_key` 一起使用 | SSL           | 设置引用的 SSL id，详见 [SSL](#ssl)。                                                                                                                                                                                                                                                                                                              | |
| tls.verify                  |否，目前仅支持 Kafka 上游。                | Boolean                       | 开启服务器证书验证功能，目前仅支持 Kafka 上游。                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |                                                                                                                                            |
|keepalive_pool.size  | 否                                             | 辅助 | 动态设置 `keepalive` 指令，详细信息请参考下文。 |
|keepalive_pool.idle_timeout  | 否                                             | 辅助 | 动态设置 `keepalive_timeout` 指令，详细信息请参考下文。 |
|keepalive_pool.requests  | 否                                             | 辅助 | 动态设置 `keepalive_requests` 指令，详细信息请参考下文。 |

`type` 详细信息如下：

- `roundrobin`: 带权重的 Round Robin。
- `chash`: 一致性哈希。
- `ewma`: 选择延迟最小的节点，请参考 [EWMA_chart](https://en.wikipedia.org/wiki/EWMA_chart)。
- `least_conn`: 选择 `(active_conn + 1) / weight` 最小的节点。此处的 `active connection` 概念跟 NGINX 的相同，它是当前正在被请求使用的连接。
- 用户自定义的 balancer，需要可以通过 `require("apisix.balancer.your_balancer")` 来加载。

`hash_on` 详细信息如下：

- 设为 `vars` 时，`key` 为必传参数，目前支持的 NGINX 内置变量有 `uri, server_name, server_addr, request_uri, remote_port, remote_addr, query_string, host, hostname, arg_***`，其中 `arg_***` 是来自 URL 的请求参数。详细信息请参考 [NGINX 变量列表](http://nginx.org/en/docs/varindex.html)。
- 设为 `header` 时，`key` 为必传参数，其值为自定义的 Header name，即 "http\_`key`"。
- 设为 `cookie` 时，`key` 为必传参数，其值为自定义的 cookie name，即 "cookie\_`key`"。请注意 cookie name 是**区分大小写字母**的。例如：`cookie_x_foo` 与 `cookie_X_Foo` 表示不同的 `cookie`。
- 设为 `consumer` 时，`key` 不需要设置。此时哈希算法采用的 `key` 为认证通过的 `consumer_name`。

以下特性需要 APISIX 运行于 [APISIX-Runtime](./FAQ.md#如何构建-APISIX-Runtime-环境？)：

- `scheme` 可以设置成 `tls`，表示 `TLS over TCP`。
- `tls.client_cert/key` 可以用来跟上游进行 mTLS 通信。他们的格式和 SSL 对象的 `cert` 和 `key` 一样。
- `tls.client_cert_id` 可以用来指定引用的 SSL 对象。只有当 SSL 对象的 `type` 字段为 client 时才能被引用，否则请求会被 APISIX 拒绝。另外，SSL 对象中只有 `cert` 和 `key` 会被使用。
- `keepalive_pool` 允许 Upstream 有自己单独的连接池。它下属的字段，比如 `requests`，可以用于配置上游连接保持的参数。

Upstream 对象 JSON 配置示例：

```shell
{
    "id": "1",                  # id
    "retries": 1,               # 请求重试次数
    "timeout": {                # 设置连接、发送消息、接收消息的超时时间，每项都为 15 秒
        "connect":15,
        "send":15,
        "read":15
    },
    "nodes": {"host:80": 100},  # 上游机器地址列表，格式为`地址 + 端口`
                                # 等价于 "nodes": [ {"host":"host", "port":80, "weight": 100} ],
    "type":"roundrobin",
    "checks": {},               # 配置健康检查的参数
    "hash_on": "",
    "key": "",
    "name": "upstream-xxx",     # upstream 名称
    "desc": "hello world",      # upstream 描述
    "scheme": "http"            # 跟上游通信时使用的 scheme，默认是 `http`
}
```

### 使用示例 {#upstream-example}

#### 创建 Upstream 并对 `nodes` 的数据进行修改 {#create-upstream}

1. 创建 Upstream：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100  \
    -H "X-API-KEY: $admin_key" -i -X PUT -d '
    {
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980": 1
        }
    }'
    ```

    ```
    HTTP/1.1 201 Created
    ...
    ```

2. 在 Upstream 中添加一个节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1981": 1
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`nodes` 将更新为：

    ```
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

3. 更新 Upstream 中单个节点的权重：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1981": 10
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`nodes` 将更新为：

    ```
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

4. 删除 Upstream 中的一个节点：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1980": null
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`nodes` 将更新为：

    ```
    {
        "127.0.0.1:1981": 10
    }
    ```

5. 更新 Upstream 的 `nodes`：

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100/nodes \
    -H "X-API-KEY: $admin_key" -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    执行成功后，`nodes` 将不再保留原来的数据：

    ```
    {
        "127.0.0.1:1982": 1
    }
    ```

#### 将客户端请求代理到上游 `https` 服务 {#proxy-https}

1. 创建 Route 并配置 Upstream 的 Scheme 为 `https`：

    ```shell
    curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/get",
        "upstream": {
            "type": "roundrobin",
            "scheme": "https",
            "nodes": {
                "httpbin.org:443": 1
            }
        }
    }'
    ```

    执行成功后，请求与上游通信时的 Scheme 将为 `https`。

2. 发送请求进行测试：

    ```shell
    curl http://127.0.0.1:9080/get
    ```

    ```shell
    {
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Host": "127.0.0.1",
        "User-Agent": "curl/7.29.0",
        "X-Amzn-Trace-Id": "Root=1-6058324a-0e898a7f04a5e95b526bb183",
        "X-Forwarded-Host": "127.0.0.1"
    },
    "origin": "127.0.0.1",
    "url": "https://127.0.0.1/get"
    }
    ```

    请求成功，表示代理上游 `https` 生效了。

    :::tip 提示

    每个节点均可以配置优先级，只有在高优先级的节点不可用或者尝试过，才会访问一个低优先级的节点。

    :::

    由于上游节点的默认优先级是 `0`，你可以将一些节点的优先级设置为负数，让其作为备份节点。例如：

    ```JSON
    {
        "uri": "/hello",
        "upstream": {
            "type": "roundrobin",
            "nodes": [
                {"host": "127.0.0.1", "port": 1980, "weight": 2000},
                {"host": "127.0.0.1", "port": 1981, "weight": 1, "priority": -1}
            ],
            "checks": {
                "active": {
                    "http_path": "/status",
                    "healthy": {
                        "interval": 1,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 1
                    }
                }
            }
        }
    }
    ```

    节点 `127.0.0.2` 只有在 `127.0.0.1` 不可用或者尝试过之后才会被访问，因此它是 `127.0.0.1` 的备份。

### 应答参数  {#upstream-response-parameters}

目前是直接返回与 etcd 交互后的结果。

## SSL

你可以使用该资源创建 SSL 证书。

### 请求地址 {#ssl-uri}

SSL 资源请求地址：/apisix/admin/ssls/{id}

### 请求方法 {#ssl-request-methods}

| 名称   | 请求 URI                | 请求 body | 描述                            |
| ------ | ----------------------- | --------- | ------------------------------- |
| GET    | /apisix/admin/ssls      | 无       | 获取资源列表。                    |
| GET    | /apisix/admin/ssls/{id} | 无       | 获取资源。                        |
| PUT    | /apisix/admin/ssls/{id} | {...}    | 创建指定 id 的资源。              |
| POST   | /apisix/admin/ssls      | {...}    | 创建资源，id 由后台服务自动生成。 |
| DELETE | /apisix/admin/ssls/{id} | 无       | 删除资源。                        |

### body 请求参数 {#ssl-body-request-methods}

| 名称        | 必选项 | 类型           | 描述                                                                                                   | 示例                                             |
| ----------- | ------ | -------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| cert        | 是     | 证书           | HTTP 证书。该字段支持使用 [APISIX Secret](./terminology/secret.md) 资源，将值保存在 Secret Manager 中。                                                                                             |                                                  |
| key         | 是     | 私钥           | HTTPS 证书私钥。该字段支持使用 [APISIX Secret](./terminology/secret.md) 资源，将值保存在 Secret Manager 中。                                                                                         |                                                  |
| certs       | 否   | 证书字符串数组 | 当你想给同一个域名配置多个证书时，除了第一个证书需要通过 `cert` 传递外，剩下的证书可以通过该参数传递上来。该字段支持使用 [APISIX Secret](./terminology/secret.md) 资源，将值保存在 Secret Manager 中。 |                                                  |
| keys        | 否   | 私钥字符串数组 | `certs` 对应的证书私钥，需要与 `certs` 一一对应。该字段支持使用 [APISIX Secret](./terminology/secret.md) 资源，将值保存在 Secret Manager 中。                                                          |                                                  |
| client.ca   | 否   | 证书 |  设置将用于客户端证书校验的 `CA` 证书。该特性需要 OpenResty 为 1.19 及以上版本。  |                                                  |
| client.depth | 否   | 辅助 |  设置客户端证书校验的深度，默认为 1。该特性需要 OpenResty 为 1.19 及以上版本。 |                                             |
| client.skip_mtls_uri_regex | 否   | PCRE 正则表达式数组 |  用来匹配请求的 URI，如果匹配，则该请求将绕过客户端证书的检查，也就是跳过 MTLS。 | ["/hello[0-9]+", "/foobar"]                                            |
| snis        | 是   | 匹配规则       | 非空数组形式，可以匹配多个 SNI。                                                                         |                                                  |
| desc        | 否   | 辅助          | 证书描述。        | certs for production env                                               |
| labels      | 否   | 匹配规则       | 标识附加属性的键值对。                                                                                   | {"version":"v2","build":"16","env":"production"} |
| type        | 否   | 辅助           | 标识证书的类型，默认值为 `server`。                                                                     | `client` 表示证书是客户端证书，APISIX 访问上游时使用；`server` 表示证书是服务端证书，APISIX 验证客户端请求时使用。     |
| status      | 否   | 辅助           | 当设置为 `1` 时，启用此 SSL，默认值为 `1`。                                                               | `1` 表示启用，`0` 表示禁用                       |
| ssl_protocols | 否    | tls 协议字符串数组               | 用于控制服务器与客户端之间使用的 SSL/TLS 协议版本。更多的配置示例，请参考[SSL 协议](./ssl-protocol.md)。                                  |                `["TLSv1.1", "TLSv1.2", "TLSv1.3"]`                                  |

SSL 对象 JSON 配置示例：

```shell
{
    "id": "1",          # id
    "cert": "cert",     # 证书
    "key": "key",       # 私钥
    "snis": ["t.com"]   # HTTPS 握手时客户端发送的 SNI
}
```

更多的配置示例，请参考[证书](./certificate.md)。

## Global Rules

Global Rule 可以设置全局运行的插件，设置为全局规则的插件将在所有路由级别的插件之前优先运行。

### 请求地址 {#global-rule-uri}

Global Rule 资源请求地址：/apisix/admin/global_rules/{id}

### 请求方法 {#global-rule-request-methods}

| 名称   | 请求 URI                               | 请求 body | 描述                                                                                                                                                                                   |
| ------ | -------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/global_rules             | 无        | 获取资源列表。                                                                                                                                                                           |
| GET    | /apisix/admin/global_rules/{id}        | 无        | 获取资源。                                                                                                                                                                               |
| PUT    | /apisix/admin/global_rules/{id}        | {...}     | 将创建指定 id 的资源。                                                                                                                                                                   |
| DELETE | /apisix/admin/global_rules/{id}        | 无        | 删除资源。                                                                                                                                                                               |
| PATCH  | /apisix/admin/global_rules/{id}        | {...}     | 标准 PATCH，修改已有 Global Rule 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为 null 即可删除；**注意**：当需要修改属性的值为数组时，该属性将全量更新。       |
| PATCH  | /apisix/admin/global_rules/{id}/{path} | {...}     | SubPath PATCH，通过 `{path}` 指定 Global Rule 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                                                                             |

### body 请求参数  {#global-rule-body-request-parameters}

| 名称        | 必选项 | 类型   | 描述                                               | 示例值       |
| ----------- | ------ | ------ | ------------------------------------------------- | ---------- |
| plugins     | 是     | Plugin | 插件配置。详细信息请参考 [Plugin](terminology/plugin.md)。 |            |

## Consumer Group

你可以使用该资源配置一组可以在 Consumer 间复用的插件。

### 请求地址 {#consumer-group-uri}

Consumer Group 资源请求地址：/apisix/admin/consumer_groups/{id}

### 请求方法 {#consumer-group-request-methods}

| 名称   | 请求 URI                                  | 请求 body | 描述                                                                                                                                                                                     |
| ------ | ----------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/consumer_groups             | 无        | 获取资源列表。                                                                                                                                                                             |
| GET    | /apisix/admin/consumer_groups/{id}        | 无        | 获取资源。                                                                                                                                                                                 |
| PUT    | /apisix/admin/consumer_groups/{id}        | {...}     | 将创建指定 id 的资源。                                                                                                                                                                        |
| DELETE | /apisix/admin/consumer_groups/{id}        | 无        | 删除资源。                                                                                                                                                                                 |
| PATCH  | /apisix/admin/consumer_groups/{id}        | {...}     | 标准 PATCH，修改已有 Consumer Group 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为 null 即可删除；**注意**：当需要修改属性的值为数组时，该属性将全量更新。 |
| PATCH  | /apisix/admin/consumer_groups/{id}/{path} | {...}     | SubPath PATCH，通过 `{path}` 指定 Consumer Group 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                                                                           |

### body 请求参数  {#consumer-group-body-request-parameters}

| 名称      | 必选项  | 类型  | 描述                                          | 示例值 |
|--------- |--------- |------|----------------------------------------------- |------|
|plugins  | 是        |Plugin| 插件配置。详细信息请参考 [Plugin](terminology/plugin.md)。 |      |
|name     | 否        | 辅助 | 消费者组名。            | premium-tier                           |
|desc     | 否        | 辅助 | 标识描述、使用场景等。                          | Consumer 测试。|
|labels   | 否        | 辅助 | 标识附加属性的键值对。                          |{"version":"v2","build":"16","env":"production"}|

## Plugin Config

你可以使用 Plugin Config 资源创建一组可以在路由间复用的插件。

### 请求地址 {#plugin-config-uri}

Plugin Config 资源请求地址：/apisix/admin/plugin_configs/{id}

### 请求方法 {#plugin-config-request-methods}

| 名称   | 请求 URI                                 | 请求 body | 描述                                                                                                                                                                                     |
| ------ | ---------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/plugin_configs             | 无        | 获取资源列表。                                                                                                                                                                             |
| GET    | /apisix/admin/plugin_configs/{id}        | 无        | 获取资源。                                                                                                                                                                                 |
| PUT    | /apisix/admin/plugin_configs/{id}        | {...}     | 根据 id 创建资源。                                                                                                                                                                         |
| DELETE | /apisix/admin/plugin_configs/{id}        | 无        | 删除资源。                                                                                                                                                                                 |
| PATCH  | /apisix/admin/plugin_configs/{id}        | {...}     | 标准 PATCH，修改已有 Plugin Config 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为 null 即可删除；**注意**：当需要修改属性的值为数组时，该属性将全量更新。 |
| PATCH  | /apisix/admin/plugin_configs/{id}/{path} | {...}     | SubPath PATCH，通过 {path} 指定 Plugin Config 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                                                                           |

### body 请求参数 {#plugin-config-body-request-parameters}

| 名称      | 必选项  | 类型 | 描述        | 示例值 |
|---------  |---------|----|-----------|----|
|plugins    | 是      |Plugin| 更多信息请参考 [Plugin](terminology/plugin.md)。||
|desc       | 否 | 辅助 | 标识描述、使用场景等。 |customer xxxx|
|labels     | 否 | 辅助 | 标识附加属性的键值对。 |{"version":"v2","build":"16","env":"production"}|

## Plugin Metadata

你可以使用 Plugin Metadata 资源配置插件元数据。

### 请求地址 {#plugin-metadata-uri}

Plugin Config 资源请求地址：/apisix/admin/plugin_metadata/{plugin_name}

### 请求方法 {#plugin-metadata-request-methods}

| Method | 请求 URI                                    | 请求 body | 描述                      |
| ------ | ------------------------------------------- | --------- | ------------------------- |
| GET    | /apisix/admin/plugin_metadata               | 无        | 获取所有插件元数据列表。    |
| GET    | /apisix/admin/plugin_metadata/{plugin_name} | 无        | 获取资源。                  |
| PUT    | /apisix/admin/plugin_metadata/{plugin_name} | {...}     | 根据 `plugin name` 创建资源。 |
| DELETE | /apisix/admin/plugin_metadata/{plugin_name} | 无        | 删除资源。                  |

### body 请求参数 {#plugin-metadata-body-request-parameters}

根据插件 (`{plugin_name}`) 的 `metadata_schema` 定义的数据结构的  JSON 对象。

### 使用示例 {#plugin-metadata-example}

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/example-plugin  \
-H "X-API-KEY: $admin_key" -i -X PUT -d '
{
    "skey": "val",
    "ikey": 1
}'
```

```
HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 04:19:34 GMT
Content-Type: text/plain
```

## Plugin

你可以通过该资源获取插件列表。

### 请求地址 {#plugin-uri}

Plugin 资源请求地址：/apisix/admin/plugins/{plugin_name}

### 请求参数

| 名称 | 描述 | 默认 |
| --------- | -------------------------------------- | -------- |
| subsystem | 插件子系统。 | http |

可以在子系统上过滤插件，以便在通过查询参数传递的子系统中搜索 ({plugin_name})

### 请求方法 {#plugin-request-methods}

| 名称        | 请求 URI                            | 请求 body | 描述          |
| ----------- | ----------------------------------- | ---------- | ------------- |
| GET         | /apisix/admin/plugins/list          | 无         | 获取资源列表。  |
| GET         | /apisix/admin/plugins/{plugin_name} | 无         | 获取资源。      |
| GET         | /apisix/admin/plugins?all=true      | 无         | 获取所有插件的所有属性。 |
| GET         | /apisix/admin/plugins?all=true&subsystem=stream| 无 | 获取所有 Stream 插件的属性。|
| GET         | /apisix/admin/plugins?all=true&subsystem=http| 无 | 获取所有 HTTP 插件的属性。|
| PUT         | /apisix/admin/plugins/reload        | 无         | 根据代码中所做的更改重新加载插件。 |
| GET         | apisix/admin/plugins/{plugin_name}?subsystem=stream         | 无         | 获取指定 Stream 插件的属性。 |
| GET         | apisix/admin/plugins/{plugin_name}?subsystem=http         | 无         | 获取指定 HTTP 插件的属性。 |

:::caution

获取所有插件属性的接口 `/apisix/admin/plugins?all=true` 将很快被弃用。

:::

### 使用示例 {#plugin-example}

获取插件  (`{plugin_name}`)  数据结构的 JSON 对象。

- 获取插件列表

    ```shell
    curl "http://127.0.0.1:9180/apisix/admin/plugins/list" \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
    ```

    ```shell
    ["zipkin","request-id",...]
    ```

- 获取指定插件的属性

    ```shell
    curl "http://127.0.0.1:9180/apisix/admin/plugins/key-auth?subsystem=http" \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
    ```

    ```json
    {"$comment":"this is a mark for our injected plugin schema","properties":{"header":{"default":"apikey","type":"string"},"hide_credentials":{"default":false,"type":"boolean"},"_meta":{"properties":{"filter":{"type":"array","description":"filter determines whether the plugin needs to be executed at runtime"},"disable":{"type":"boolean"},"error_response":{"oneOf":[{"type":"string"},{"type":"object"}]},"priority":{"type":"integer","description":"priority of plugins by customized order"}},"type":"object"},"query":{"default":"apikey","type":"string"}},"type":"object"}
    ```

:::tip

你可以使用 `/apisix/admin/plugins?all=true` 接口获取所有插件的所有属性，每个插件包括 `name`，`priority`，`type`，`schema`，`consumer_schema` 和 `version`。

这个 API 将很快被弃用。

:::

## Stream Route

Stream Route 是用于 TCP/UDP 动态代理的路由。详细信息请参考 [TCP/UDP 动态代理](./stream-proxy.md)。

### 请求地址 {#stream-route-uri}

Plugin 资源请求地址：/apisix/admin/stream_routes/{id}

### 请求方法 {#stream-route-request-methods}

| 名称   | 请求 URI                          | 请求 body | 描述                                               |
| ------ | --------------------------------- | --------- | -------------------------------------------------- |
| GET    | /apisix/admin/stream_routes       | 无        | 获取资源列表。                                     |
| GET    | /apisix/admin/stream_routes/{id}  | 无        | 获取资源。                                        |
| PUT    | /apisix/admin/stream_routes/{id}  | {...}     | 创建指定 id 的资源。                              |
| POST   | /apisix/admin/stream_routes       | {...}     | 创建资源，id 由后台服务自动生成。                  |
| DELETE | /apisix/admin/stream_routes/{id}  | 无        | 删除资源。                                        |

### body 请求参数{#stream-route-body-request-parameters}

| 名称             | 必选项 | 类型     | 描述                                                                           | 示例值 |
| ---------------- | ------| -------- | ------------------------------------------------------------------------------| ------  |
| name             | 否    | 辅助     | Stream 路由名。            | postgres-proxy                                   |
| desc             | 否    | 辅助     | Stream 路由描述。          | proxy endpoint for postgresql                    |
| labels           | 否    | 匹配规则  | 标识附加属性的键值对。           | {"version":"17","service":"user","env":"production"} |
| upstream         | 否    | Upstream | Upstream 配置，详细信息请参考 [Upstream](terminology/upstream.md)。             |         |
| upstream_id      | 否    | Upstream | 需要使用的 Upstream id，详细信息请 [Upstream](terminology/upstream.md)。       |         |
| service_id       | 否    | String   | 需要使用的 [Service](terminology/service.md) id.                   |                               |
| remote_addr      | 否    | IPv4, IPv4 CIDR, IPv6  | 过滤选项：如果客户端 IP 匹配，则转发到上游                                      | "127.0.0.1" 或 "127.0.0.1/32" 或 "::1" |
| server_addr      | 否    | IPv4, IPv4 CIDR, IPv6  | 过滤选项：如果 APISIX 服务器的 IP 与 `server_addr` 匹配，则转发到上游。         | "127.0.0.1" 或 "127.0.0.1/32" 或 "::1" |
| server_port      | 否    | 整数     | 过滤选项：如果 APISIX 服务器的端口 与 `server_port` 匹配，则转发到上游。        | 9090  |
| sni              | 否    | Host     | 服务器名称。                                                                   | "test.com"     |
| protocol.name    | 否    | 字符串   | xRPC 框架代理的协议的名称。                                                    | "redis"        |
| protocol.conf    | 否    | 配置     | 协议特定的配置。                                                               |                    |

你可以查看 [Stream Proxy](./stream-proxy.md#更多-route-匹配选项) 了解更多过滤器的信息。

## Secret

Secret 指的是 `Secrets Management`（密钥管理），可以使用任何支持的密钥管理器，例如 `vault`。

### 请求地址 {#secret-config-uri}

Secret 资源请求地址：/apisix/admin/secrets/{secretmanager}/{id}

### 请求方法 {#secret-config-request-methods}

| 名称 | 请求 URI                          | 请求 body | 描述                                        |
| :--: | :----------------------------: | :---: | :---------------------------------------: |
| GET  | /apisix/admin/secrets            | NULL  | 获取所有 secret 的列表。                  |
| GET  | /apisix/admin/secrets/{manager}/{id} | NULL  | 根据 id 获取指定的 secret。           |
| PUT  | /apisix/admin/secrets/{manager}            | {...} | 创建新的 secret 配置。                              |
| DELETE | /apisix/admin/secrets/{manager}/{id} | NULL   | 删除具有指定 id 的 secret。 |
| PATCH  | /apisix/admin/secrets/{manager}/{id}        | {...}     | 标准 PATCH，修改指定 secret 的部分属性，其他不涉及的属性会原样保留；如果你需要删除某个属性，可以将该属性的值设置为 `null`；当需要修改属性的值为数组时，该属性将全量更新。 |
| PATCH  | /apisix/admin/secrets/{manager}/{id}/{path} | {...}     | SubPath PATCH，通过 `{path}` 指定 secret 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。                         |

### body 请求参数 {#secret-config-body-requset-parameters}

#### 当 Secret Manager 是 Vault 时

| 名称  | 必选项 | 类型        | 描述                                                                                                        | 例子                                          |
| ----------- | -------- | ----------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| uri    | 是     | URI        |  Vault 服务器的 URI                                                 |                                                  |
| prefix    | 是    | 字符串       | 密钥前缀
| token     | 是    | 字符串       | Vault 令牌 |                                                  |
| namespace | 否    | 字符串       | Vault 命名空间，该字段无默认值 | `admin` |

配置示例：

```shell
{
    "uri": "https://localhost/vault",
    "prefix": "/apisix/kv",
    "token": "343effad"
}

```

使用示例：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/secrets/vault/test2 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "http://xxx/get",
    "prefix" : "apisix",
    "token" : "apisix"
}'
```

```shell
HTTP/1.1 200 OK
...

{"key":"\/apisix\/secrets\/vault\/test2","value":{"id":"vault\/test2","token":"apisix","prefix":"apisix","update_time":1669625828,"create_time":1669625828,"uri":"http:\/\/xxx\/get"}}
```

#### 当 Secret Manager 是 AWS 时

| 名称              | 必选项 | 默认值                                        | 描述                    |
| ----------------- | ------ | --------------------------------------------- | ----------------------- |
| access_key_id     | 是     |                                               | AWS 访问密钥 ID         |
| secret_access_key | 是     |                                               | AWS 访问密钥            |
| session_token     | 否     |                                               | 临时访问凭证信息        |
| region            | 否     | us-east-1                                     | AWS 区域                |
| endpoint_url      | 否     | https://secretsmanager.{region}.amazonaws.com | AWS Secret Manager 地址 |

配置示例：

```json
{
    "endpoint_url": "http://127.0.0.1:4566",
    "region": "us-east-1",
    "access_key_id": "access",
    "secret_access_key": "secret",
    "session_token": "token"
}

```

使用示例：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/secrets/aws/test3 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "endpoint_url": "http://127.0.0.1:4566",
    "region": "us-east-1",
    "access_key_id": "access",
    "secret_access_key": "secret",
    "session_token": "token"
}'
```

```shell
HTTP/1.1 200 OK
...

{"value":{"create_time":1726069970,"endpoint_url":"http://127.0.0.1:4566","region":"us-east-1","access_key_id":"access","secret_access_key":"secret","id":"aws/test3","update_time":1726069970,"session_token":"token"},"key":"/apisix/secrets/aws/test3"}
```

#### 当 Secret Manager 是 GCP 时

| 名称                     | 必选项 | 默认值                                         | 描述                                                                                                                              |
| ------------------------ | ------ | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| auth_config              | 是     |                                                | `auth_config` 和 `auth_file` 必须配置一个。                                                                                       |
| auth_config.client_email | 是     |                                                | 谷歌服务帐号的 email 参数。                                                                                                       |
| auth_config.private_key  | 是     |                                                | 谷歌服务帐号的私钥参数。                                                                                                          |
| auth_config.project_id   | 是     |                                                | 谷歌服务帐号的项目 ID。                                                                                                           |
| auth_config.token_uri    | 否     | https://oauth2.googleapis.com/token            | 请求谷歌服务帐户的令牌的 URI。                                                                                                    |
| auth_config.entries_uri  | 否     | https://secretmanager.googleapis.com/v1        | 谷歌密钥服务访问端点 API。                                                                                                        |
| auth_config.scope        | 否     | https://www.googleapis.com/auth/cloud-platform | 谷歌服务账号的访问范围，可参考 [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes) |
| auth_file                | 是     |                                                | `auth_config` 和 `auth_file` 必须配置一个。                                                                                       |
| ssl_verify               | 否     | true                                           | 当设置为 `true` 时，启用 `SSL` 验证。                                                                                             |

配置示例：

```json
{
    "auth_config" : {
        "client_email": "email@apisix.iam.gserviceaccount.com",
        "private_key": "private_key",
        "project_id": "apisix-project",
        "token_uri": "https://oauth2.googleapis.com/token",
        "entries_uri": "https://secretmanager.googleapis.com/v1",
        "scope": ["https://www.googleapis.com/auth/cloud-platform"]
    }
}

```

使用示例：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/secrets/gcp/test4 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "auth_config" : {
        "client_email": "email@apisix.iam.gserviceaccount.com",
        "private_key": "private_key",
        "project_id": "apisix-project",
        "token_uri": "https://oauth2.googleapis.com/token",
        "entries_uri": "https://secretmanager.googleapis.com/v1",
        "scope": ["https://www.googleapis.com/auth/cloud-platform"]
    }
}'
```

```shell
HTTP/1.1 200 OK
...

{"value":{"id":"gcp/test4","ssl_verify":true,"auth_config":{"token_uri":"https://oauth2.googleapis.com/token","scope":["https://www.googleapis.com/auth/cloud-platform"],"entries_uri":"https://secretmanager.googleapis.com/v1","client_email":"email@apisix.iam.gserviceaccount.com","private_key":"private_key","project_id":"apisix-project"},"create_time":1726070161,"update_time":1726070161},"key":"/apisix/secrets/gcp/test4"}
```

### 应答参数 {#secret-config-response-parameters}

当前的响应是从 etcd 返回的。
