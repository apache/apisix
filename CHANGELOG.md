# Table of Contents

- [0.6.0](#060)


## [0.6.0]

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
- support multiple ips of `allow`. [340](https://github.com/iresty/apisix/pull/340)
- supported real_ip configure in nginx.conf and added functions to get ip and remote ip. [#236](https://github.com/iresty/apisix/pull/236)

### Dashboard
- :sunrise: **add built-in dashboard**. [#327](https://github.com/iresty/apisix/pull/327)

### Test
- support OSX in Travis CI. [#217](https://github.com/iresty/apisix/pull/217)
- installed all of the dependencies to `deps` folder. [#248](https://github.com/iresty/apisix/pull/248)

[Back to TOC](#table-of-contents)
