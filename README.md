# Summary

APISIX 是一个基于云原生、高速可扩展的开源微服务网关节点实现，其自身主要优势是高性能和强大的扩展性。

APISIX 从 `etcd` 中订阅获取所需的配置并以热更新的方式来更改自身行为，更改 `etcd` 中的配置即可完成对 APISIX
网关节点的控制，比如：动态上游、请求限速等。

## Route

`Route` 是如何匹配用户请求的具体描述。目前 APISIX 还只支持 `URI` 和 `Method` 两种方式匹配
用户请求。其他比如 `Host` 方式，将会持续增加。

## Service

`Service` 某类功能的提供者，比如订单、账户服务。它通常与上游服务抽象是一对一的，`Route`
与 `Service` 之间，通常是 N:1 的关系，既多个 `Route` 规则可以对应同一个 `Service`。

# Consumer

`Consumer` 是某类具体服务的消费者，主要用来表述不同用户的概念。比如不用的客户请求同一个 API，
经过用户认证体系，网关服务需知道当前请求用户身份信息，针对不同的消费用户，会有不同的限制处理逻辑。

## Plugin

`Plugin` 表示将在 `HTTP` 请求/响应生命周期期间执行的插件配置。
`Plugin` 配置可直接绑定在 `Route` 上，也可以被绑定在 `Service` 或 `Consumer`上。而对于同一
个插件的配置，只能有一份是有效的，配置选择优先级总是 `Consumer` > `Route` > `Service`。

# Design Doc

### How to load the plugin?

![](doc/flow-load-plugin.png)


# Development

### Source Install

> Dependent library

* [lua-resty-r3] Setups the [resty-r3#install](https://github.com/iresty/lua-resty-r3#install) library.
* [lua-resty-etcd] Setups the [resty-etcd#install](https://github.com/iresty/lua-resty-etcd#install) library.
* [lua-resty-balancer] Setups the [resty-balancer#install](https://github.com/iresty/lua-resty-balancer#installation) library.

> Install by luarocks

```shell
luarocks install lua-resty-r3 lua-resty-etcd lua-resty-balancer
```

### User routes with plugins config in etcd

Here is example for one route and one upstream:

```shell
$ curl http://127.0.0.1:2379/v2/keys/user_routes/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 649,
        "key": "/user_routes/1",
        "modifiedIndex": 649,
        "value": "{\"host\":\"test.com\",\"methods\":[\"GET\"],\"uri\":\"/hello\",\"id\":3333,\"plugin_config\":{\"example-plugin\":{\"i\":1,\"s\":\"s\",\"t\":[1,2]},\"new-plugin\":{\"a\":\"a\"}},\"upstream\":{\"id\":1,\"type\":\"roundrobin\"}}"
    }
}

$ curl http://127.0.0.1:2379/v2/keys/user_upstreams/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 679,
        "key": "/user_upstreams/1",
        "modifiedIndex": 679,
        "value": "{\"id\":1,\"type\":\"roundrobin\",\"nodes\":{\"220.181.57.215:80\":1,\"220.181.57.216:80\":1,\"220.181.57.217:80\":1}}"
    }
}
```

Here is example for one route (it contains the upstream information):

```
$ curl http://127.0.0.1:2379/v2/keys/user_routes/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 649,
        "key": "/user_routes/1",
        "modifiedIndex": 649,
        "value": "{\"host\":\"test.com\",\"methods\":[\"GET\"],\"uri\":\"/hello\",\"id\":3333,\"plugin_config\":{\"example-plugin\":{\"i\":1,\"s\":\"s\",\"t\":[1,2]},\"new-plugin\":{\"a\":\"a\"}},\"upstream\":{\"type\":\"roundrobin\",\"nodes\":{\"220.181.57.215:80\":1,\"220.181.57.216:80\":1,\"220.181.57.217:80\":1}}}"
    }
}
```
