
目录
===

* [Route](#route)

## Route

*说明*：Route 字面意思就是路由，通过定义一些规则来匹配客户端的请求，然后根据匹配结果加载并执行相应的
插件，并把请求转发给到指定 Upstream。

> 请求参数

|名字      |可选项   |类型 |说明        |
|---------|---------|----|-----------|
|uri      |必须 |匹配规则|除了如 `/foo/bar`、`/foo/gloo` 这种全量匹配外，使用不同 [Router](architecture-design-cn.md#router) 还允许更高级匹配，更多见 [Router](architecture-design-cn.md#router)。|
|host     |可选 |匹配规则|当前请求域名，比如 `foo.com`；也支持泛域名，比如 `*.foo.com`。|
|hosts    |可选 |匹配规则|数组形态的 host，表示允许有多个不同 host，匹配其中任意一个即可。|
|remote_addr|可选 |匹配规则|客户端请求 IP 地址，比如 `192.168.1.101`、`192.168.1.102`，也支持 CIDR 格式如 `192.168.1.0/24`。特别的，APISIX 也完整支持 IPv6 地址匹配，比如：`::1`，`fe80::1`, `fe80::1/64` 等。|
|remote_addrs|可选 |匹配规则|数组形态的 remote_addr，表示允许有多个不同 IP 地址，符合其中任意一个即可。|
|methods  |可选 |匹配规则|如果为空或没有该选项，代表没有任何 `method` 限制，也可以是一个或多个的数组组合组合：GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS，CONNECT，TRACE。|
|vars       |可选  |匹配规则(仅支持 radixtree 路由)|由一个或多个`{var, operator, val}`元素组成的数组，类似这样：{{var, operator, val}, {var, operator, val}, ...}。例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于 `operator` 部分，目前已支持的运算符有 `==`、`~=`、`>`和`<`，特别的对于后面两个运算符，会把结果先转换成 number 然后再做比较。|
|filter_fun |可选  |匹配规则(仅支持 radixtree 路由)|用户自定义过滤规则函数脚本，比如：`function (vars) if vars["arg_name"] == "json" end`。|
|plugins  |可选 |Plugin|详见 [Plugin](architecture-design-cn.md#plugin) |
|upstream |可选 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design-cn.md#upstream)|
|upstream_id|可选 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design-cn.md#upstream)|
|service_id|可选 |Service|绑定的 Service 配置，详见 [Service](architecture-design-cn.md#service)|

> 应答参数

目前是直接返回与 etcd 交互后的结果。
