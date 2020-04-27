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

# 目录

* [Route](#route)
* [Service](#service)
* [Consumer](#consumer)
* [Upstream](#upstream)
* [SSL](#ssl)

## Route

*地址*：/apisix/admin/routes/{id}?ttl=0

*说明*：Route 字面意思就是路由，通过定义一些规则来匹配客户端的请求，然后根据匹配结果加载并执行相应的
插件，并把请求转发给到指定 Upstream。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/routes/{id}|无|获取资源|
|PUT      |/apisix/admin/routes/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/routes     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/routes/{id}|无|删除资源|
|PATCH    |/apisix/admin/routes/{id}/{path}|{...}|修改已有 Route 的部分内容，其他不涉及部分会原样保留。|

> uri 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|ttl     |可选 |辅助   |超过这个时间会被自动删除，单位：秒|ttl=1|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|uri      |与 `uris` 二选一 |匹配规则|除了如 `/foo/bar`、`/foo/gloo` 这种全量匹配外，使用不同 [Router](architecture-design-cn.md#router) 还允许更高级匹配，更多见 [Router](architecture-design-cn.md#router)。|"/hello"|
|uris     |与 `uri` 二选一 |匹配规则|数组形式，可以匹配多个 `uri`|["/hello", "/world"]|
|plugins  |`plugins`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Plugin|详见 [Plugin](architecture-design-cn.md#plugin) ||
|upstream |`plugins`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design-cn.md#upstream)||
|upstream_id|`plugins`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design-cn.md#upstream)||
|service_id|`plugins`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Service|绑定的 Service 配置，详见 [Service](architecture-design-cn.md#service)||
|service_protocol|可选|上游协议类型|只可以是 "grpc", "http" 二选一。|默认 "http"，使用gRPC proxy 或gRPC transcode 时，必须用"grpc"|
|desc     |可选 |辅助   |标识路由名称、使用场景等。|客户 xxxx|
|host     |可选 |匹配规则|当前请求域名，比如 `foo.com`；也支持泛域名，比如 `*.foo.com`。|"foo.com"|
|hosts    |可选 |匹配规则|列表形态的 `host`，表示允许有多个不同 `host`，匹配其中任意一个即可。|{"foo.com", "*.bar.com"}|
|remote_addr|可选 |匹配规则|客户端请求 IP 地址: `192.168.1.101`、`192.168.1.102` 以及 CIDR 格式的支持 `192.168.1.0/24`。特别的，APISIX 也完整支持 IPv6 地址匹配：`::1`，`fe80::1`, `fe80::1/64` 等。|"192.168.1.0/24"|
|remote_addrs|可选 |匹配规则|列表形态的 `remote_addr`，表示允许有多个不同 IP 地址，符合其中任意一个即可。|{"127.0.0.1", "192.0.0.0/8", "::1"}|
|methods  |可选 |匹配规则|如果为空或没有该选项，代表没有任何 `method` 限制，也可以是一个或多个的组合：`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`，`CONNECT`，`TRACE`。|{"GET", "POST"}|
|priority  |可选 |匹配规则|如果不同路由包含相同 `uri`，根据属性 `priority` 确定哪个 `route` 被优先匹配，值越大优先级越高，默认值为 0。|priority = 10|
|vars       |可选  |匹配规则|由一个或多个`{var, operator, val}`元素组成的列表，类似这样：`{{var, operator, val}, {var, operator, val}, ...}`。例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 Nginx 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于 `operator` 部分，目前已支持的运算符有 `==`、`~=`、`>`、`<` 和 `~~`。对于`>`和`<`两个运算符，会把结果先转换成 number 然后再做比较。查看支持的[运算符列表](#运算符列表)|{{"arg_name", "==", "json"}, {"arg_age", ">", 18}}|
|filter_func|可选|匹配规则|用户自定义的过滤函数。可以使用它来实现特殊场景的匹配要求实现。该函数默认接受一个名为 vars 的输入参数，可以用它来获取 Nginx 变量。|function(vars) return vars["arg_name"] == "json" end|

有两点需要特别注意：

* 除了 `uri`/`uris` 是必选的之外，`plugins`、`upstream`/`upstream_id`、`service_id` 这三类必须选择其中至少一个。
* 对于同一类参数比如 `uri`与 `uris`，`upstream` 与 `upstream_id`，`host` 与 `hosts`，`remote_addr` 与 `remote_addrs` 等，是不能同时存在，二者只能选择其一。如果同时启用，接口会报错。

route 对象 json 配置内容：

```shell
{
    "id": "1",                  # id，非必填
    "uri": "/release/a",        # uri 路径
    "uris": ["/a","/b"],        # 一组 uri 路径， uri 与 uris 只需要有一个非空即可
    "methods": ["GET","POST"],  # 可以填多个方法
    "host": "aa.com",           # host 域名
    "hosts": ["a.com","b.com"], # 一组 host 域名， host 与 hosts 只需要有一个非空即可
    "plugins": {},              # 指定 route 绑定的插件
    "priority": 0,              # apisix 支持多种匹配方式，可能会在一次匹配中同时匹配到多条路由，此时优先级高的优先匹配中
    "desc": "hello world",
    "remote_addr": "127.0.0.1", # 客户端请求 IP 地址
    "remote_addrs": ["127.0.0.1"],  # 一组客户端请求 IP 地址， remote_addr 与 remote_addrs 只需要有一个非空即可
    "vars": [],                 # 由一个或多个 {var, operator, val} 元素组成的列表
    "upstream_id": "1",         # upstream 对象在 etcd 中的 id ，建议使用此值
    "upstream": {},             # upstream 信息对象，建议尽量不要使用
    "filter_func": "",          # 用户自定义的过滤函数，非必填
}
```

具体示例：

```shell
# 创建一个路由
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/index.html",
    "hosts": ["foo.com", "*.bar.com"],
    "remote_addrs": ["127.0.0.0/8"],
    "methods": ["PUT", "GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...

# 创建一个有效期为 60 秒的路由，过期后自动删除
$ curl http://127.0.0.1:9080/apisix/admin/routes/2?ttl=60 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/aa/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...

```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

### 运算符列表

|运算符   |描述       |例子|
|--------|-----------|-------|
|==      |相等      |{"arg_name", "==", "json"}|
|~=      |不等于    |{"arg_name", "~=", "json"}|
|>       |大于      |{"arg_age", ">", 24}|
|<       |小于      |{"arg_age", "<", 24}|
|~~      |正则匹配   |{"arg_name", "~~", "[a-z]+"}|

请看下面例子，匹配请求参数 name 等于 json ，age 大于 18 且 address 开头是 China 的请求：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/index.html",
    "vars": [
        ["arg_name", "==", "json"],
        ["arg_age", ">", "18"],
        ["arg_address", "~~", "^China.*"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

[Back to TOC](#目录)

## Service

*地址*：/apisix/admin/services/{id}

*说明*：`Service` 是某类 API 的抽象（也可以理解为一组 Route 的抽象）。它通常与上游服务抽象是一一对应的，`Route`
与 `Service` 之间，通常是 N:1 的关系。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/services/{id}|无|获取资源|
|PUT      |/apisix/admin/services/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/services     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/services/{id}|无|删除资源|
|PATCH    |/apisix/admin/services/{id}/{path}|{...}|修改已有 Service 的部分内容，其他不涉及部分会原样保留。|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|plugins  |可选 |Plugin|详见 [Plugin](architecture-design-cn.md#plugin) ||
|upstream | upstream 或 upstream_id 两个选一个 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design-cn.md#upstream)||
|upstream_id| upstream 或 upstream_id 两个选一个 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design-cn.md#upstream)||
|desc     |可选 |辅助   |标识服务名称、使用场景等。||

serivce 对象 json 配置内容：

```shell
{
    "id": "1",              # id
    "plugins": {},          # 指定 service 绑定的插件
    "upstream_id": "1",     # upstream 对象在 etcd 中的 id ，建议使用此值
    "upstream": {},         # upstream 信息对象，不建议使用
    "desc": "hello world",  # service 描述
}
```

具体示例：

```shell
# 创建一个Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -X PUT -i -d '
{
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

# 返回结果

HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 03:48:47 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 3600
Server: APISIX web server

{"node":{"value":{"upstream":{"nodes":{"39.97.63.215:80":1},"type":"roundrobin"},"plugins":{"limit-count":{"time_window":60,"count":2,"rejected_code":503,"key":"remote_addr","policy":"local"}}},"createdIndex":60,"key":"\/apisix\/services\/201","modifiedIndex":60},"action":"set"}
```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## Consumer

*地址*：/apisix/admin/consumers/{id}

*说明*：Consumer 是某类服务的消费者，需与用户认证体系配合才能使用。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/consumers/{id}|无|获取资源|
|PUT      |/apisix/admin/consumers/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/consumers     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/consumers/{id}|无|删除资源|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|username|必需|辅助|Consumer 名称。||
|plugins|可选|Plugin|该 Consumer 对应的插件配置，它的优先级是最高的：Consumer > Route > Service。对于具体插件配置，可以参考 [Plugins](#plugin) 章节。||
|desc     |可选 |辅助|consumer描述||

consumer 对象 json 配置内容：

```shell
{
    "id": "1",              # id
    "plugins": {},          # 指定 consumer 绑定的插件
    "username": "name",     # 必填
    "desc": "hello world",  # consumer 描述
}
```

绑定认证授权插件有些特别，当它需要与 consumer 联合使用时，需要提供用户名、密码等信息；另一方面，当它与 route/service 绑定时，是不需要任何参数的。因为这时候是根据用户请求数据来反向推出用户对应的是哪个 consumer

示例：

```shell
# 创建 Consumer ，指定认证插件 key-auth ，并开启特定插件 limit-count
$ curl http://127.0.0.1:9080/apisix/admin/consumers/2 -X PUT -i -d '
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
HTTP/1.1 200 OK
Date: Thu, 26 Dec 2019 08:17:49 GMT
...

{"node":{"value":{"username":"jack","plugins":{"key-auth":{"key":"auth-one"},"limit-count":{"time_window":60,"count":2,"rejected_code":503,"key":"remote_addr","policy":"local"}}},"createdIndex":64,"key":"\/apisix\/consumers\/jack","modifiedIndex":64},"prevNode":{"value":"{\"username\":\"jack\",\"plugins\":{\"key-auth\":{\"key\":\"auth-one\"},\"limit-count\":{\"time_window\":60,\"count\":2,\"rejected_code\":503,\"key\":\"remote_addr\",\"policy\":\"local\"}}}","createdIndex":63,"key":"\/apisix\/consumers\/jack","modifiedIndex":63},"action":"set"}
```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## Upstream

*地址*：/apisix/admin/upstreams/{id}

*说明*：Upstream 是虚拟主机抽象，对给定的多个服务节点按照配置规则进行负载均衡。Upstream 的地址信息可以直接配置到 `Route`（或 `Service`) 上，当 Upstream 有重复时，就需要用“引用”方式避免重复了。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/upstreams/{id}|无|获取资源|
|PUT      |/apisix/admin/upstreams/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/upstreams     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/upstreams/{id}|无|删除资源|
|PATCH    |/apisix/admin/upstreams/{id}/{path}|{...}|修改已有 Route 的部分内容，其他不涉及部分会原样保留。|

> body 请求参数：

APISIX 的 Upstream 除了基本的复杂均衡算法选择外，还支持对上游做主被动健康检查、重试等逻辑，具体看下面表格。

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|nodes           |与 `k8s_deployment_info` 二选一|Node|哈希表，内部元素的 key 是上游机器地址列表，格式为`地址 + Port`，其中地址部分可以是 IP 也可以是域名，比如 `192.168.1.100:80`、`foo.com:80`等。value 则是节点的权重，特别的，当权重值为 `0` 有特殊含义，通常代表该上游节点失效，永远不希望被选中。|`192.168.1.100:80`|
|k8s_deployment_info|与 `nodes` 二选一|哈希表|字段包括 `namespace`、`deploy_name`、`service_name`、`port`、`backend_type`，其中 `port` 字段为数值，`backend_type` 为 `pod` 或 `service`，其他为字符串 | `{"namespace": "test-namespace", "deploy_name": "test-deploy-name", "service_name": "test-service-name", "backend_type": "pod", "port": 8080}` |
|type            |必需|枚举|`roundrobin` 支持权重的负载，`chash` 一致性哈希，两者是二选一的|`roundrobin`||
|key             |条件必需|匹配类型|该选项只有类型是 `chash` 才有效。根据 `key` 来查找对应的 node `id`，相同的 `key` 在同一个对象中，永远返回相同 id，目前支持的 Nginx 内置变量有 `uri, server_name, server_addr, request_uri, remote_port, remote_addr, query_string, host, hostname, arg_***`，其中 `arg_***` 是来自URL的请求参数，[Nginx 变量列表](http://nginx.org/en/docs/varindex.html)||
|checks          |可选|health_checker|配置健康检查的参数，详细可参考[health-check](health-check.md)||
|retries         |可选|整型|使用底层的 Nginx 重试机制将请求传递给下一个上游，默认不启用重试机制||
|timeout         |可选|超时时间对象|设置连接、发送消息、接收消息的超时时间||
|enable_websocket     |可选 |辅助|是否允许启用 websocket 能力||
|hash_on     |可选 |辅助|该参数作为一致性 hash 的入参||
|desc     |可选 |辅助|标识服务名称、使用场景等。||

upstream 对象 json 配置内容：

```shell
{
    "id": "1",                  # id
    "retries": 0,               # 请求重试次数
    "timeout": {                # 设置连接、发送消息、接收消息的超时时间
        "connect":15,
        "send":15,
        "read":15,
    },
    "enable_websocket": true,
    "nodes": {"host:80": 100},  # 上游机器地址列表，格式为`地址 + Port`
    "k8s_deployment_info": {    # k8s deployment 信息
        "namespace": "test-namespace",
        "deploy_name": "test-deploy-name",
        "service_name": "test-service-name",
        "backend_type": "pod",   # pod or service
        "port": 8080
    },
    "type":"roundrobin",        # chash or roundrobin
    "checks": {},               # 配置健康检查的参数
    "hash_on": "",
    "key": "",
    "desc": "hello world",      # upstream 描述
}
```

具体示例：

```shell
# 创建一个upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -i -X PUT -d '
> {
>     "type": "roundrobin",
>     "nodes": {
>         "127.0.0.1:80": 1,
>         "127.0.0.2:80": 2,
>         "foo.com:80": 3
>     }
> }'
HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 04:19:34 GMT
Content-Type: text/plain
...

{"node":{"value":{"nodes":{"127.0.0.1:80":1,"foo.com:80":3,"127.0.0.2:80":2},"type":"roundrobin"},"createdIndex":61,"key":"\/apisix\/upstreams\/100","modifiedIndex":61},"action":"set"}

```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## SSL

*地址*：/apisix/admin/ssl/{id}

*说明*：SSL.

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/ssl/{id}|无|获取资源|
|PUT      |/apisix/admin/ssl/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/ssl     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/ssl/{id}|无|删除资源|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|cert|必需|公钥|https 证书公钥||
|key|必需|私钥|https 证书私钥||
|sni|必需|匹配规则|https 证书SNI||

ssl 对象 json 配置内容：

```shell
{
    "id": "1",          # id
    "cert": "cert",     # 公钥
    "key": "key",       # 私钥
    "sni": "sni"        # host 域名
}
```

[Back to TOC](#目录)
