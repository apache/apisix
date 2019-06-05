## name

[![Build Status](https://travis-ci.org/iresty/apisix.svg?branch=master)](https://travis-ci.org/iresty/apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/apisix/blob/master/LICENSE)

Apisix 是一个基于云原生、高速可扩展的开源微服务网关节点实现，其自身主要优势是高性能和强大的扩展性。

Apisix 从 `etcd` 中订阅获取所需的配置并以热更新的方式来更改自身行为，更改 `etcd` 中的配置即可完成对 Apisix
网关节点的控制，比如：动态上游、请求限速等。

## Summary
- [**Name**](#name)
- [**Apisix Config**](#apisix-config)
- [**Route**](#route)
- [**Service**](#service)
- [**Consumer**](#consumer)
- [**Plugin**](#plugin)
- [**Join us**](#join-us)


## Apisix Config

通过修改本地 `conf/config.yaml` 文件完成对 Apisix 服务本身的基本配置。

```yaml
apisix:
  node_listen: 9080             # Apisix listening port

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

*注意* 不要手工修改 Apisix 自身的 `conf/nginx.conf` 文件，当服务每次启动时，`apisix`
会根据 `conf/config.yaml` 配置自动生成新的 `conf/nginx.conf` 并自动启动服务。

目前读写 `etcd` 操作使用的是 v2 协议，所有配置均存储在 `/v2/keys` 目录下。

[Back to TOC](#summary)

## Route

默认路径：`/apisix/routes/****`

`Route` 是如何匹配用户请求的具体描述。目前 Apisix 支持 `URI` 和 `Method` 两种方式匹配
用户请求。其他比如 `Host` 方式，将会持续增加。

路径中的 `key` 会被用作路由 `id` 做唯一标识，比如下面示例的路由 `id` 是 `100`。

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/100 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": "100",
    "plugin_config": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

#### Route option

|name     |option   |description|
|---------|---------|-----------|
|uri      |required |除了静态常量匹配，还支持正则 `/foo/{:\w+}/{:\w+}`，更多见 [lua-resty-libr3](https://github.com/iresty/lua-resty-libr3)|
|id       |required |必须与路径中的 `key` 保持一致|
|methods  |optional |如果为空或没有该选项，代表没有任何 `method` 限制，也可以是一个或多个组合：GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS。|
|plugin_config|required |启用的插件配置，详见 [Plugin](#plugin) |
|upstream|required |启用的上游配置，详见 [Upstream](#upstream)|
|service_id|optional |绑定的 Service 配置，详见 [Service](#service)|


[Back to TOC](#summary)

## Service

*还未完整覆盖测试*

`Service` 某类功能的提供者，比如订单、账户服务。它通常与上游服务抽象是一对一的，`Route`
与 `Service` 之间，通常是 N:1 的关系，既多个 `Route` 规则可以对应同一个 `Service`。

多个 route 规则同时绑定到一个 service 上，这些路由将具有相同的上游和插件配置，减少冗余配置。

比如下面的例子，id 分别是 `100`、`101` 的 route 都绑定了同一个 id 为 `200` 的 service
上，它们都启用了相同的限速插件。

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/services/200 -X PUT -d value='
{
    "id": "200",
    "plugin_config": {
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

curl http://127.0.0.1:2379/v2/keys/apisix/routes/100 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": "100",
    "service_id": "200"
}'

curl http://127.0.0.1:2379/v2/keys/apisix/routes/101 -X PUT -d value='
{
    "methods": [],
    "uri": "/foo/index.html",
    "id": "101",
    "service_id": "200"
}'
```

当然也可以对具体路由指定更高级别的个性插件配置。比如下面的例子，为这个新 route 设置了不同的插件
参数：

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/102 -X PUT -d value='
{
    "methods": [],
    "uri": "/bar/index.html",
    "id": "102",
    "service_id": "200",
    "plugin_config": {
        "limit-count": {
            "count": 2000,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}'
```

也就是说，当 route 和 server 的配置出现冲突时，route 的优先级是要高于 service 的。

[Back to TOC](#summary)

## Consumer

*还未完整覆盖测试*

`Consumer` 是某类具体服务的消费者，主要用来表述不同用户的概念。比如不用的客户请求同一个 API，
经过用户认证体系，网关服务需知道当前请求用户身份信息，针对不同的消费用户，会有不同的限制处理逻辑。

[Back to TOC](#summary)

## Plugin

`Plugin` 表示将在 `HTTP` 请求/响应生命周期期间执行的插件配置。
`Plugin` 配置可直接绑定在 `Route` 上，也可以被绑定在 `Service` 或 `Consumer`上。而对于同一
个插件的配置，只能有一份是有效的，配置选择优先级总是 `Consumer` > `Route` > `Service`。

在 `conf/config.yaml` 中，可以声明本地 apisix 节点都支持哪些插件。这是个白名单机制，不在该
白名单的插件配置，都将会被自动忽略。这个特性可用于临时关闭或打开特定插件，应对突发情况非常有效。

插件的配置可以被直接绑定在指定 route 中，也可以被绑定在 service 中，不过 route 中的插件配置
优先级更高。

一个插件在一次请求中只会执行一次，即使被同时绑定到多个不同对象中（比如 route 或 service）。
插件运行先后顺序是根据插件自身的优先级来决定的，例如：[example-plugin](https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/example-plugin.lua#L16)。

插件配置作为 route 或 service 的一部分提交的，放到 `plugin_config` 下。它内部是使用插件
名字作为哈希的 key 来保存不同插件的配置项。

```json
{
    ...
    "plugin_config": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    }
    ...
}
```

并不是所有插件都有具体配置项，比如 `prometheus` 下是没有任何具体配置项，这时候用一个空的对象
标识即可。

目前自带的插件，有下面几个：

* [key-auth](https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/key-auth.md)
* [limit-count](https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/limit-count.md)
* [limit-req](https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/limit-req.md)
* [prometheus](https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/prometheus.md)

[Back to TOC](#summary)

## Upstream

上游对象表示虚拟主机名，可用于通过多个服务（目标）对传入请求进行负载均衡。

上游的配置使用，与 plugin 非常相似。也可以同时被绑定到 route 或 service 上，并根据优先级决
定优先使用谁。

* type
    * roundrobin：支持权重的负载
    * chash：一致性 hash (TODO)
* nodes: 上游机器地址列表（暂不支持域名）

```json
{
    ...
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.100:80": 1,
            "39.97.63.200:80": 2
        }
    }
    ...
}
```

[Back to TOC](#summary)

## Join us

如果你对 Apisix 的开发和使用感兴趣，欢迎加入我们的 QQ 群来交流:

![](doc/qq-group.png)
