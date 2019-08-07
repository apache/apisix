# Table of Contents

- [0.6.0](#060)


## [0.6.0]

> Released on 2019/08/05

这个版本带来很多新的特性，比如健康检查、服务熔断、debug 模式，分布式追踪、JWT
认证等，以及**内置的 dashboard**.

### Core
- :sunrise: **[健康检查和服务熔断](https://github.com/iresty/apisix/blob/master/doc/health-check.md)**: 对上游节点开启健康检查，智能判断服务状态进行熔断和连接. [#249](https://github.com/iresty/apisix/pull/249)
- 阻止ReDoS(Regular expression Denial of Service). [#252](https://github.com/iresty/apisix/pull/250)
- 支持 debug 模式. [#319](https://github.com/iresty/apisix/pull/319)
- 允许自定义路由. [#364](https://github.com/iresty/apisix/pull/364)
- 路由支持 host 和 uri 的组合. [#325](https://github.com/iresty/apisix/pull/325)
- 允许在 balance 阶段注入插件. [#299](https://github.com/iresty/apisix/pull/299)
- 为 upstream 和 service 在 schema 中增加描述信息. [#289](https://github.com/iresty/apisix/pull/289)

### Plugins
- :sunrise: **[分布式追踪 OpenTracing](https://github.com/iresty/apisix/blob/master/doc/plugins/zipkin.md)**: 支持 Zipkin 和 Apache SkyWalking. [#304](https://github.com/iresty/apisix/pull/304)
- [JWT 认证](https://github.com/iresty/apisix/blob/master/doc/plugins/jwt-auth-cn.md). [#303](https://github.com/iresty/apisix/pull/303)

### CLI
- `allow` 指令中支持多个 ip 地址. [340](https://github.com/iresty/apisix/pull/340)
- 支持在 nginx.conf 中配置 real_ip 指令，以及增加函数来获取 ip. [#236](https://github.com/iresty/apisix/pull/236)

### Dashboard
- :sunrise: **增加内置的 dashboard**. [#327](https://github.com/iresty/apisix/pull/327)

### Test
- 在 Travis CI 中支持 OSX. [#217](https://github.com/iresty/apisix/pull/217)
- 把所有依赖安装到 `deps` 目录. [#248](https://github.com/iresty/apisix/pull/248)

[Back to TOC](#table-of-contents)
