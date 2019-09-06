# Table of Contents

- [0.7.0](#070)
- [0.6.0](#060)


## 0.7.0

> Released on 2019/09/06

这个版本带来很多新的特性，比如 IP 黑白名单、gPRC 协议转换、支持 IPv6、对接 IdP（身份认证提供商）服务、serverless、radix tree 路由等。

### Core
- :sunrise: **[gRPC 协议转换](https://github.com/iresty/apisix/blob/master/doc/plugins/grpc-transcoding-cn.md)**: 支持 gRPC 协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API. [#395](https://github.com/iresty/apisix/issues/395)
- :sunrise: **[radix tree 路由](https://github.com/iresty/apisix/blob/master/doc/router-radixtree.md)**: 将 radix tree 作为默认的路由器实现，支持把 uri、host、cookie、请求头、请求参数、Nginx 内置变量等作为路由的条件，并支持等于、大于、小于等常见操作符，更加强大和灵活. [#414](https://github.com/iresty/apisix/issues/414)
- 动态上游支持更多的参数，可以指定上游的 uri 和 host，以及是否开启 websocket. [#451](https://github.com/iresty/apisix/pull/451)
- 支持从 `ctx.var` 中直接获取 cookie 中的值. [#449](https://github.com/iresty/apisix/pull/449)
- 路由支持 IPv6. [#331](https://github.com/iresty/apisix/issues/331)

### Plugins
- :sunrise: **[serverless](https://github.com/iresty/apisix/blob/master/doc/plugins/serverless-cn.md)**: 支持 serverless，用户可以把任意 Lua 函数动态的在网关节点上运行。用户也可以把这个功能当做是轻量级的插件来使用。[#86](https://github.com/iresty/apisix/pull/86)
- :sunrise: **IdP 支持**: 支持外部的身份认证服务，比如 Auth0，okta 等，用户可以借此来对接 Oauth2.0 等认证方式。 [#447](https://github.com/iresty/apisix/pull/447)
- [限流限速](https://github.com/iresty/apisix/blob/master/doc/plugins/limit-conn-cn.md)支持更多的限制 key，比如 X-Forwarded-For 和 X-Real-IP，并且允许用户把 Nginx 变量、请求头和请求参数作为 key. [#228](https://github.com/iresty/apisix/issues/228)
- [IP 黑白名单](https://github.com/iresty/apisix/blob/master/doc/plugins/ip-restriction.md) 支持 IP 黑白名单，提供更高的安全性。[#398](https://github.com/iresty/apisix/pull/398)

### CLI
- 增加 `version` 指令，获取 APISIX 的版本号. [#420](https://github.com/iresty/apisix/issues/420)

### Admin
- 支持 `PATCH` API，可以针对某个配置单独修改，而不再用提交整段配置。[#365](https://github.com/iresty/apisix/pull/365)

### Dashboard
- :sunrise: **增加在线版本的 dashboard**，用户不用安装即可[体验 APISIX](http://apisix.iresty.com/). [#374](https://github.com/iresty/apisix/issues/374)


[Back to TOC](#table-of-contents)


## 0.6.0

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
- `allow` 指令中支持多个 ip 地址. [#340](https://github.com/iresty/apisix/pull/340)
- 支持在 nginx.conf 中配置 real_ip 指令，以及增加函数来获取 ip. [#236](https://github.com/iresty/apisix/pull/236)

### Dashboard
- :sunrise: **增加内置的 dashboard**. [#327](https://github.com/iresty/apisix/pull/327)

### Test
- 在 Travis CI 中支持 OSX. [#217](https://github.com/iresty/apisix/pull/217)
- 把所有依赖安装到 `deps` 目录. [#248](https://github.com/iresty/apisix/pull/248)

[Back to TOC](#table-of-contents)
