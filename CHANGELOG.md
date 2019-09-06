# Table of Contents


- [0.7.0](#070)
- [0.6.0](#060)


## 0.7.0

> Released on 2019/09/06

This release brings many new features, such as IP black and white list, gPRC protocol transcoding, IPv6, IdP (identity provider) services, serverless, radix tree routing, and more.

### Core
- :sunrise: **[gRPC transcoding](https://github.com/iresty/apisix/blob/master/doc/plugins/grpc-transcoding.md)**: supports protocol transcoding so that clients can access your gRPC API by using HTTP/JSON. [#395](https://github.com/iresty/apisix/issues/395)
- :sunrise: **[radix tree router](https://github.com/iresty/apisix/blob/master/doc/router-radixtree.md)**: The radix tree is used as the default router implementation. It supports the uri, host, cookie, request header, request parameters, Nginx built-in variables, etc. as the routing conditions, and supports common operators such as equal, greater than, less than, etc., more powerful and flexible. [#414](https://github.com/iresty/apisix/issues/414)
- Dynamic upstream supports more parameters, you can specify the upstream uri and host, and whether to enable websocket. [#451](https://github.com/iresty/apisix/pull/451)
- Support for get values from cookies directly from `ctx.var`. [#449](https://github.com/iresty/apisix/pull/449)
- Routing support IPv6. [#331](https://github.com/iresty/apisix/issues/331)

### Plugins
- :sunrise: **[serverless](https://github.com/iresty/apisix/blob/master/doc/plugins/serverless.md)**: With serverless support, users can dynamically run any Lua function on a gateway node. Users can also use this feature as a lightweight plugin.[#86](https://github.com/iresty/apisix/pull/86)
- :sunrise: **support IdP**: Support external authentication services, such as Auth0, okta, etc., users can use this to connect to Oauth2.0 and other authentication methods. [#447](https://github.com/iresty/apisix/pull/447)
- [rate limit](https://github.com/iresty/apisix/blob/master/doc/plugins/limit-conn.md): Support for more restricted keys, such as `X-Forwarded-For` and `X-Real-IP`, and allows users to use Nginx variables, request headers, and request parameters as keys. [#228](https://github.com/iresty/apisix/issues/228)
- [IP black and white list](https://github.com/iresty/apisix/blob/master/doc/plugins/ip-restriction.md) Support IP black and white list for security. [#398](https://github.com/iresty/apisix/pull/398)

### CLI
- Add the `version` directive to get the version number of APISIX. [#420](https://github.com/iresty/apisix/issues/420)

### Admin
- The `PATCH` API is supported and can be modified individually for a configuration without submitting the entire configuration. [#365](https://github.com/iresty/apisix/pull/365)

### Dashboard
- :sunrise: **Add the online version of the dashboard**，users can [experience APISIX](http://apisix.iresty.com/) without install. [#374](https://github.com/iresty/apisix/issues/374)


[Back to TOC](#table-of-contents)


## 0.6.0

> Released on 2019/08/05

This release brings many new features such as health check and circuit breaker, debug mode, opentracing and JWT auth. And add **built-in dashboard**.

### Core
- :sunrise: **[Health Check and Circuit Breaker](https://github.com/iresty/apisix/blob/master/doc/health-check.md)**: Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability. [#249](https://github.com/iresty/apisix/pull/249)
- Anti-ReDoS(Regular expression Denial of Service). [#252](https://github.com/iresty/apisix/pull/250)
- supported debug mode. [#319](https://github.com/iresty/apisix/pull/319)
- allowed to use different router. [#364](https://github.com/iresty/apisix/pull/364)
- supported to match route by host + uri. [#325](https://github.com/iresty/apisix/pull/325)
- allowed plugins to handler balance phase. [#299](https://github.com/iresty/apisix/pull/299)
- added desc for upstream and service in schema. [#289](https://github.com/iresty/apisix/pull/289)

### Plugins
- :sunrise: **[OpenTracing](https://github.com/iresty/apisix/blob/master/doc/plugins/zipkin.md)**: support Zipkin and Apache SkyWalking. [#304](https://github.com/iresty/apisix/pull/304)
- [JWT auth](https://github.com/iresty/apisix/blob/master/doc/plugins/jwt-auth-cn.md). [#303](https://github.com/iresty/apisix/pull/303)

### CLI
- support multiple ips of `allow`. [#340](https://github.com/iresty/apisix/pull/340)
- supported real_ip configure in nginx.conf and added functions to get ip and remote ip. [#236](https://github.com/iresty/apisix/pull/236)

### Dashboard
- :sunrise: **add built-in dashboard**. [#327](https://github.com/iresty/apisix/pull/327)

### Test
- support OSX in Travis CI. [#217](https://github.com/iresty/apisix/pull/217)
- installed all of the dependencies to `deps` folder. [#248](https://github.com/iresty/apisix/pull/248)

[Back to TOC](#table-of-contents)
