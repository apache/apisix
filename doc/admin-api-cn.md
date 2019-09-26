
目录
===

* [Route](#route)

## Route

*地址*：/apisix/admin/routes/{id}

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

> 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|desc     |可选 |辅助   |标识路由名称、使用场景等。|客户 xxxx|
|uri      |必须 |匹配规则|除了如 `/foo/bar`、`/foo/gloo` 这种全量匹配外，使用不同 [Router](architecture-design-cn.md#router) 还允许更高级匹配，更多见 [Router](architecture-design-cn.md#router)。|"/hello"|
|host     |可选 |匹配规则|当前请求域名，比如 `foo.com`；也支持泛域名，比如 `*.foo.com`。|"foo.com"|
|hosts    |可选 |匹配规则|列表形态的 `host`，表示允许有多个不同 `host`，匹配其中任意一个即可。|{"foo.com", "*.bar.com"}|
|remote_addr|可选 |匹配规则|客户端请求 IP 地址: `192.168.1.101`、`192.168.1.102` 以及 CIDR 格式的支持 `192.168.1.0/24`。特别的，APISIX 也完整支持 IPv6 地址匹配：`::1`，`fe80::1`, `fe80::1/64` 等。|"192.168.1.0/24"|
|remote_addrs|可选 |匹配规则|列表形态的 `remote_addr`，表示允许有多个不同 IP 地址，符合其中任意一个即可。|{"127.0.0.1", "192.0.0.0/8", "::1"}|
|methods  |可选 |匹配规则|如果为空或没有该选项，代表没有任何 `method` 限制，也可以是一个或多个的组合：`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`，`CONNECT`，`TRACE`。|{"GET", "POST"}|
|vars       |可选  |匹配规则(仅支持 `radixtree` 路由)|由一个或多个`{var, operator, val}`元素组成的列表，类似这样：`{{var, operator, val}, {var, operator, val}, ...}`。例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于 `operator` 部分，目前已支持的运算符有 `==`、`~=`、`>`和`<`，特别的对于后面两个运算符，会把结果先转换成 number 然后再做比较。|{{"arg_name", "==", "json"}, {"arg_age", ">", 18}}|
|plugins  |可选 |Plugin|详见 [Plugin](architecture-design-cn.md#plugin) ||
|upstream |可选 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design-cn.md#upstream)||
|upstream_id|可选 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design-cn.md#upstream)||
|service_id|可选 |Service|绑定的 Service 配置，详见 [Service](architecture-design-cn.md#service)||
|service_protocol|可选|上游协议类型|只可以是 "grpc", "http" 二选一。|默认 "http"|

对于同一类参数比如 `host` 与 `hosts`，`remote_addr` 与 `remote_addrs`，是不能同时存在，二者只能选择其一。如果同时启用，接口会报错。

示例：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -i -d '
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
```

> 应答参数

目前是直接返回与 etcd 交互后的结果。
