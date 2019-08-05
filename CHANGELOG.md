# Table of Contents

- [0.6.0](#060)


## [0.6.0]

> Released on 2019/08/05

This release brings many new features such as health check and circuit breaker, debug mode, opentracing and JWT auth. And add built-in **dashboard**.

### Core
- :sunrise: **[Health Check and Circuit Breaker](https://github.com/iresty/apisix/blob/master/doc/health-check.md)**: Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.[#249](https://github.com/iresty/apisix/pull/249)
- Anti-ReDoS(Regular expression Denial of Service) [#252](https://github.com/iresty/apisix/pull/250)
- support debug mode. [#319](https://github.com/iresty/apisix/pull/319)

### Plugins
- :sunrise: **[OpenTracing](https://github.com/iresty/apisix/blob/master/doc/plugins/zipkin.md)**: support Zipkin and Apache SkyWalking. [#304](https://github.com/iresty/apisix/pull/304)
- [JWT auth](https://github.com/iresty/apisix/blob/master/doc/plugins/jwt-auth-cn.md). [#303](https://github.com/iresty/apisix/pull/303)

### Dashboard
- :sunrise: add built-in dashboard. [#327](https://github.com/iresty/apisix/pull/327)

### Test
- support OSX in Travis CI. [#217](https://github.com/iresty/apisix/pull/217)

[Back to TOC](#table-of-contents)
