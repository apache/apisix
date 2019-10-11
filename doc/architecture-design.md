## Table of Contents
- [**APISIX**](#apisix)
- [**APISIX Config**](#apisix-config)
- [**Route**](#route)
- [**Service**](#service)
- [**Plugin**](#plugin)
- [**Upstream**](#upstream)
- [**Router**](#router)
- [**Consumer**](#consumer)
- [**Debug mode**](#Debug-mode)

## APISIX

### Plugin Loading Process

![](./images/flow-load-plugin.png)

### Plugin Hierarchy Structure

<img src="./images/flow-plugin-internal.png" width="50%" height="50%">

## APISIX Config

We can start using APISIX just by modifying `conf/config.yaml` file.

```yaml
apisix:
  node_listen: 9080             # APISIX listening port

etcd:
  host: "http://127.0.0.1:2379" # etcd address
  prefix: "apisix"              # apisix configurations prefix
  timeout: 60

plugins:                        # plugin name list
  - example-plugin
  - limit-req
  - limit-count
  - ...
```

*Note* `apisix` will generate `conf/nginx.conf` file automatically, so please *DO NOT EDIT* that file.

[Back to top](#Table-of-contents)

## Route

The route matches the client's request by defining rules, then loads and executes the corresponding plugin based on the matching result, and forwards the request to the specified Upstream.

The route mainly consists of three parts: matching rules (e.g uri, host, remote_addr, etc.), plugin configuration (current-limit & rate-limit, etc.) and upstream information.

The following image shows an example of some Route rules. When some attribute values are the same, the figure is identified by the same color.

<img src="./images/routes-example.png" width="50%" height="50%">

We configure all the parameters directly in the Route, it's easy to set up, and each Route has a relatively high degree of freedom. But when our Route has more repetitive configurations (such as enabling the same plugin configuration or upstream information), once we need update these same properties, we have to traverse all the Routes and modify them, so it adding a lot of complexity of management and maintenance.

The shortcomings mentioned above are independently abstracted in APISIX by the two concepts [Service](#service) and [Upstream](#upstream).

The route example created below is to proxy the request with uri `/index.html` to the Upstream service with the address `39.97.63.215:80`:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -i -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/index.html","upstream":{"nodes":{"39.97.63.215:80":1},"type":"roundrobin"}},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925},"action":"create"}
```

When we receive a successful response, it indicates that the route was successfully created.

For specific options of Route, please refer to [Admin API](admin-api-cn.md#route).

[Back to top](#Table-of-contents)

## Service

A `Service` is an abstraction of an API (which can also be understood as a set of Route abstractions). It usually corresponds to the upstream service abstraction. Between `Route` and `Service`, usually the relationship of N:1, please see the following image.

<img src="./images/service-example.png" width="50%" height="50%">

Different Route rules are bound to a Service at the same time. These Routes will have the same upstream and plugin configuration, reducing redundant configuration.

The following example creates a Service that enables the current-limit plugin, and then binds the Route with the id of `100` and `101` to the Service.

```shell
# create new Service
$ curl http://127.0.0.1:9080/apisix/admin/services/200 -X PUT -d '
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

# create new Route and reference the service by id `200`
curl http://127.0.0.1:9080/apisix/admin/routes/100 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "service_id": "200"
}'

curl http://127.0.0.1:9080/apisix/admin/routes/101 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/foo/index.html",
    "service_id": "200"
}'
```

Of course, we can also specify different plugin parameters or upstream for Route. Some of the following Routes have different current-limit parameters. Other parts (such as upstream) continue to use the configuration parameters in Service.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/102 -X PUT -d '
{
    "uri": "/bar/index.html",
    "id": "102",
    "service_id": "200",
    "plugins": {
        "limit-count": {
            "count": 2000,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}'
```

Note: When both Route and Service enable the same plugin, the Route parameter has a higher priority than Service.

[Back to top](#Table-of-contents)

## Plugin

`Plugin` represents the plugin configuration that will be executed during the `HTTP` request/response lifecycle.

The `Plugin` configuration can be bound directly to `Route` or it can be bound to `Service` or `Consumer`. For the configuration of the same plugin, only one copy is valid, and the configuration selection priority is always `Consumer` > `Route` > `Service`.

In `conf/config.yaml`, you can declare which plugins are supported by the local APISIX node. This is a whitelisting mechanism. Plugins that are not in this whitelist will be automatically ignored. This feature can be used to temporarily turn off or turn on specific plugins, which is very effective in dealing with unexpected situations.

The configuration of the plugin can be directly bound to the specified Route, or it can be bound to the Service, but the plugin configuration in Route has a higher priority.

A plugin will only be executed once in a single request, even if it is bound to multiple different objects (such as Route or Service).

The order in which plugins are run is determined by the priority of the plugin itself, for example: [example-plugin](../doc/plugins/example-plugin.lua#L16)。

The plugin configuration is submitted as part of Route or Service and placed under `plugins`. It internally uses the plugin name as the hash's key to hold configuration items for different plugins.

```json
{
    ...
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    }
}
```

Not all plugins have specific configuration items. For example, there is no specific configuration item under `prometheus`. In this case, an empty object identifier can be used.

[APISIX supported plugin list](plugins-cn.md)

[Back to top](#Table-of-contents)

## Upstream

Upstream is a virtual host abstraction that performs load balancing on a given set of service nodes according to configuration rules. Upstream address information can be directly configured to `Route` (or `Service`). When Upstream has duplicates, you need to use "reference" to avoid duplication.

<img src="./images/upstream-example.png" width="50%" height="50%">

As shown in the image above, by creating an Upstream object and referencing it by ID in `Route`, you can ensure that only the value of an object is maintained.

Upstream configuration can be directly bound to the specified `Route` or it can be bound to `Service`, but the configuration in `Route` has a higher priority. The priority behavior here is very similar to `Plugin`.

#### Configuration

In addition to the basic complex equalization algorithm selection, APISIX's Upstream also supports logic for upstream passive health check and retry, see the table below.

|name    |Optional|Description|
|-------         |-----|------|
|type            |required|`roundrobin` supports the weight of the load, `chash` consistency hash, pick one of them.|
|nodes           |required|Hash table, the key of the internal element is the upstream machine address list, the format is `Address + Port`, where the address part can be IP or domain name, such as `192.168.1.100:80`, `foo.com:80`, etc. Value is the weight of the node. In particular, when the weight value is `0`, it has a special meaning, which usually means that the upstream node is invalid and never wants to be selected.|
|key             |required|This option is only valid if the type is `chash`. Find the corresponding node `id` according to `key`, the same `key` in the same object, always return the same id.|
|checks          |optional|Configure the parameters of the health check. For details, refer to [health-check](health-check.md).|
|retries         |optional|Pass the request to the next upstream using the underlying Nginx retry mechanism, the retry mechanism is not enabled by default.|

Create an upstream object use case:

```json
curl http://127.0.0.1:9080/apisix/admin/upstreams/1 -X PUT -d '
{
    "type": "roundrobin",
    "nodes": {
        "127.0.0.1:80": 1,
        "127.0.0.2:80": 2,
        "foo.com:80": 3
    }
}'

curl http://127.0.0.1:9080/apisix/admin/upstreams/2 -X PUT -d '
{
    "type": "chash",
    "key": "remote_addr",
    "nodes": {
        "127.0.0.1:80": 1,
        "foo.com:80": 2
    }
}'
```

After the upstream object is created, it can be referenced by specific `Route` or `Service`, for example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "upstream_id": 2
}'
```

For convenience, you can also directly bind the upstream address to a `Route` or `Service`, for example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
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
```

Here's an example of configuring a health check:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
         "nodes": {
            "39.97.63.215:80": 1
        }
        "type": "roundrobin",
        "retries": 2,
        "checks": {
            "active": {
                "http_path": "/status",
                "host": "foo.com",
                "healthy": {
                    "interval": 2,
                    "successes": 1
                },
                "unhealthy": {
                    "interval": 1,
                    "http_failures": 2
                }
            }
        }
    }
}'
```

More details can be found in [Health Checking Documents](health-check.md).

[Back to top](#Table-of-contents)


## Router

A distinguishing feature of APISIX from other API gateways is that it allows users to choose different routers to better match free services, making the best choice between performance and freedom.

Set the route that best suits your business needs in the local configuration `conf/config.yaml`.

* `apisix.router.http`: HTTP Request Route。
    * `radixtree_uri`: (Default) only use `uri` as the primary index. Support for full and deep prefix matching based on the `radix tree` engine, see [How to use router-radixtree](router-radixtree.md).
        * `Absolute match `: Complete match for the given `uri` , such as `/foo/bar`,`/foo/glo`.
        * `Prefix match`: Use `*` at the end to represent the given `uri` as a prefix match. For example, `/foo*` allows matching `/foo/`, `/foo/a` and `/foo/b`.
        * `match priority`: first try absolute match, if you can't hit absolute match, try prefix match.
        * `Any filter attribute`: Allows you to specify any Ningx built-in variable as a filter, such as uri request parameters, request headers, cookies, and so on.
    * `r3_uri`: Use only `uri` as the primary index (based on the r3 engine). The trie tree based on `r3` supports regular matching, such as `/foo/{:\w+}/{:\w+}`, see [How to use router-r3](router-r3.md).
    * `r3_host_uri`: Use `host + uri` as the primary index (based on the r3 engine), matching both host and uri for the current request.

* `apisix.router.ssl`: SSL loads the matching route.
    * `radixtree_sni`: (Default) Use `SNI` (Server Name Indication) as the primary index (based on the radixtree engine).
    * `r3_sni`: Use `SNI` (Server Name Indication) as the primary index (based on the r3 engine).

[Back to top](#Table-of-contents)

## Consumer

对于 API 网关通常可以用请求域名、客户端 IP 地址等字段识别到某类请求方，
然后进行插件过滤并转发请求到指定上游，但有时候这个深度不够。

<img src="./images/consumer-who.png" width="50%" height="50%">

如上图所示，作为 API 网关，需要知道 API Consumer（消费方）具体是谁，这样就可以对不同 API Consumer 配置不同规则。

|字段|必选|说明|
|---|----|----|
|username|是|Consumer 名称。|
|plugins|否|该 Consumer 对应的插件配置，它的优先级是最高的：Consumer > Route > Service。对于具体插件配置，可以参考 [Plugins](#plugin) 章节。|

在 APISIX 中，识别 Consumer 的过程如下图：

<img src="./images/consumer-internal.png" width="50%" height="50%">

1. 授权认证：比如有 [key-auth](./plugins/key-auth.md)、[JWT](./plugins/jwt-auth-cn.md) 等。
2. 获取 consumer_id：通过授权认证，即可自然获取到对应的 Consumer `id`，它是 Consumer 对象的唯一识别标识。
3. 获取 Consumer 上绑定的 Plugin 或 Upstream 信息：完成对不同 Consumer 做不同配置的效果。

概括一下，Consumer 是某类服务的消费者，需与用户认证体系配合才能使用。
比如不同的 Consumer 请求同一个 API，网关服务根据当前请求用户信息，对应不同的 Plugin 或 Upstream 配置。

此外，大家也可以参考 [key-auth](./plugins/key-auth.md) 认证授权插件的调用逻辑，辅助大家来进一步理解 Consumer 概念和使用。

如何对某个 Consumer 开启指定插件，可以看下面例子：

```shell
# 创建 Consumer ，指定认证插件 key-auth ，并开启特定插件 limit-count
$ curl http://127.0.0.1:9080/apisix/admin/consumers/1 -X PUT -d '
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

# 创建 Router，设置路由规则和启用插件配置
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "plugins": {
        "key-auth": {}
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'

# 发测试请求，前两次返回正常，没达到限速阈值
$ curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
...

$ curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
...

# 第三次测试返回 503，请求被限制
$ curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
HTTP/1.1 503 Service Temporarily Unavailable
...

```

[Back to top](#Table-of-contents)

## Debug mode

### Basic Debug Mode

Enable basic debug mode just by setting `apisix.enable_debug = true` in `conf/config.yaml` file.

e.g Using both `limit-conn` and `limit-count` plugins for a `/hello` request, there will have a response header called `Apisix-Plugins: limit-conn, limit-count`.

```shell
$ curl http://127.0.0.1:1984/hello -i
HTTP/1.1 200 OK
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Apisix-Plugins: limit-conn, limit-count
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: openresty

hello world
```

### Advanced Debug Mode

Enable advanced debug mode by modifying the configuration in `conf/debug.yaml` file. Because there will have a check every second, only the checker reads the `#END` flag, and the file would consider as closed.

The checker would judge whether the file data changed according to the last modification time of the file. If there has any change, reload it. If there was no change, skip this check. So it's hot reload for enabling or disabling advanced debug mode.

|Key|Optional|Description|Default|
|----|-----|---------|---|
|hook_conf.enable|required|Enable/Disable hook debug trace. Target module function's input arguments or returned value would be printed once this option is enabled.|false|
|hook_conf.name|required|The module list name of hook which has enabled debug trace||
|hook_conf.log_level|required|Logging levels for input arguments & returned value|warn|
|hook_conf.is_print_input_args|required|Enable/Disable input arguments print|true|
|hook_conf.is_print_return_value|required|Enable/Disable returned value print|true|

Example:

```yaml
hook_conf:
  enable: false                 # Enable/Disable Hook Debug Trace
  name: hook_phase              # The Module List Name of Hook which has enabled Debug Trace
  log_level: warn               # Logging Levels
  is_print_input_args: true     # Enable/Disable Input Arguments Print
  is_print_return_value: true   # Enable/Disable Returned Value Print

hook_phase:                     # Module Function List, Name: hook_phase
  apisix:                       # Referenced Module Name
    - http_access_phase         # Function Names：Array
    - http_header_filter_phase
    - http_body_filter_phase
    - http_log_phase

#END
```

[Back to top](#Table-of-contents)
