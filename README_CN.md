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
  prefix: "/v2/keys/apisix"     # etcd prefix
  timeout: 60

plugins:                        # plugin name list
  - example-plugin
  - limit-req
  - limit-count
  - ...
```

*注意* 不要手工修改 Apisix 自身的 `conf/nginx.conf` 文件，当服务每次启动时，`apisix`
会根据 `conf/config.yaml` 配置自动生成新的 `conf/nginx.conf` 并自动启动服务。

[Back to TOC](#summary)

## Route

默认路径：`/v2/keys/apisix/routes/****`

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

[Back to TOC](#summary)

## Upstream

[Back to TOC](#summary)

## Join us

如果你对 Apisix 的开发和使用感兴趣，欢迎加入我们的 QQ 群来交流:

![](doc/qq-group.png)
