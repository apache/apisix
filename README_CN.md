# Summary

[![Build Status](https://travis-ci.org/iresty/apisix.svg?branch=master)](https://travis-ci.org/iresty/apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/apisix/blob/master/LICENSE)

APISIX 是一个基于云原生、高速可扩展的开源微服务网关节点实现，其自身主要优势是高性能和强大的扩展性。

APISIX 从 `etcd` 中订阅获取所需的配置并以热更新的方式来更改自身行为，更改 `etcd` 中的配置即可完成对 APISIX
网关节点的控制，比如：动态上游、请求限速等。

如果你对 APISIX 的开发和使用感兴趣，欢迎加入我们的 QQ 群来交流:
![](doc/qq-group.png)

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
