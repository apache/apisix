<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

# Table of Contents

- [0.9.0-RC1](#090-rc1)
- [0.8.0](#080)
- [0.7.0](#070)
- [0.6.0](#060)


## 0.9.0-RC1
> Released on 2019/11/11

This release brings many new features, such as support for running APISIX with Tengine,
an advanced debugging mode that is more developer friendly, and a new URI redirection plugin.

### Core
- :sunrise: Supported to run APISIX with tengine. [#683](https://github.com/apache/incubator-apisix/pull/683)
- :sunrise: Enabled HTTP2 and supported to set ssl_protocols. [#663](https://github.com/apache/incubator-apisix/pull/663)
- :sunrise: Advanced Debug Mode, Target module function's input arguments or returned value would be printed once this option is enabled. [#614](https://github.com/apache/incubator-apisix/pull/641)
- Support to install APISIX without dashboard. [#686](https://github.com/apache/incubator-apisix/pull/686)
- Removed router R3 [#725](https://github.com/apache/incubator-apisix/pull/725)

### Plugins
- [Redirect URI](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/redirect.md):【New Plugin】Redirect URI plugin. [#732](https://github.com/apache/incubator-apisix/pull/732)
- [Proxy Rewrite](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/proxy-rewrite.md):【New Feature】Supported remove `header` feature. [#658](https://github.com/apache/incubator-apisix/pull/658)
- [Limit Count](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/limit-count.md):【New Feature】Supported global limit count with `Redis Server`.[#624](https://github.com/apache/incubator-apisix/pull/624)

### lua-resty-*
- lua-resty-radixtree
    - 【New Feature】Support for `host + uri` as an index.
- lua-resty-jsonschema
    - 【New Plugin】This extension is a JSON data validator that replaces the existing `lua-rapidjson` extension.

### Bugfix
- 【Bug】key-auth plugin cannot run accurately in the case of multiple consumers. [#826](https://github.com/apache/incubator-apisix/pull/826)
- 【Bug】Exported schema for plugin serverless. [#787](https://github.com/apache/incubator-apisix/pull/787)
- 【Bug】Discard args of uri when using proxy-write plugin [#642](https://github.com/apache/incubator-apisix/pull/642)
- 【Bug】Zipkin plugin not set tracing data to request header. [#715](https://github.com/apache/incubator-apisix/pull/715)
- 【Optimization】Skipped check cjson for luajit environment in apisix CLI. [#652](https://github.com/apache/incubator-apisix/pull/652)
- 【Optimization】Skipped to init etcd if use local file as config center. [#737](https://github.com/apache/incubator-apisix/pull/737)
- 【Optimization】Support more built-in parameters when set chash balancer. [#775](https://github.com/apache/incubator-apisix/pull/775)

### Dependencies
- Replace the `lua-rapidjson` module with `lua-resty-jsonschema` global,  `lua-resty-jsonschema` is faster and easier to compile.


## 0.8.0
> Released on 2019/09/30

This release brings many new features, such as stream proxy, support MQTT protocol proxy,
and support for ARM platform, and proxy rewrite plugin.

### Core
- :sunrise: **[support stand-alone mode](https://github.com/apache/incubator-apisix/blob/master/doc/stand-alone-cn.md)**: using yaml to update configurations of APISIX, more friendly to kubernetes. [#464](https://github.com/apache/incubator-apisix/pull/464)
- :sunrise: **[support stream proxy](https://github.com/apache/incubator-apisix/blob/master/doc/stream-proxy.md)**. [#513](https://github.com/apache/incubator-apisix/pull/513)
- :sunrise: support consumer bind plugins. [#544](https://github.com/apache/incubator-apisix/pull/544)
- support domain name in upstream, not only IP. [#522](https://github.com/apache/incubator-apisix/pull/522)
- ignored upstream node when it's weight is 0. [#536](https://github.com/apache/incubator-apisix/pull/536)

### Plugins
- :sunrise: **[MQTT Proxy](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/mqtt-proxy.md)**: support to load balance MQTT by `client_id`, both support MQTT 3.1 and 5.0. [#513](https://github.com/apache/incubator-apisix/pull/513)
- [proxy-rewrite](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/proxy-rewrite.md): rewrite uri,
 schema, host for upstream. [#594](https://github.com/apache/incubator-apisix/pull/594)

### ARM
- :sunrise: **APISIX can run normally under Ubuntu 18.04 of ARM64 architecture**, so you can use APISIX as IoT gateway with MQTT plugin.

### lua-resty-*
- lua-resty-ipmatcher
    - support IPv6
    - IP white/black list, route.
- lua-resty-radixtree
    - allow to specify multiple host, remote_addr and uri.
    - allow to define user-function to filter request.
    - use `lua-resty-ipmatcher` instead of `lua-resty-iputils`, `lua-resty-ipmatcher` matches fast and support IPv6.


### Bugfix
- healthcheck: the checker name is wrong if APISIX works under multiple processes. [#568](https://github.com/apache/incubator-apisix/issues/568)

### Dependencies
- removed `lua-tinyyaml` from source code base, and install through Luarocks.

## 0.7.0

> Released on 2019/09/06

This release brings many new features, such as IP black and white list, gPRC protocol transcoding, IPv6, IdP (identity provider) services, serverless, Change the default route to radix tree (**not downward compatible**), and more.

### Core
- :sunrise: **[gRPC transcoding](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/grpc-transcoding.md)**: supports protocol transcoding so that clients can access your gRPC API by using HTTP/JSON. [#395](https://github.com/apache/incubator-apisix/issues/395)
- :sunrise: **[radix tree router](https://github.com/apache/incubator-apisix/blob/master/doc/router-radixtree.md)**: The radix tree is used as the default router implementation. It supports the uri, host, cookie, request header, request parameters, Nginx built-in variables, etc. as the routing conditions, and supports common operators such as equal, greater than, less than, etc., more powerful and flexible.**IMPORTANT: This change is not downward compatible. All users who use historical versions need to manually modify their routing to work properly.** [#414](https://github.com/apache/incubator-apisix/issues/414)
- Dynamic upstream supports more parameters, you can specify the upstream uri and host, and whether to enable websocket. [#451](https://github.com/apache/incubator-apisix/pull/451)
- Support for get values from cookies directly from `ctx.var`. [#449](https://github.com/apache/incubator-apisix/pull/449)
- Routing support IPv6. [#331](https://github.com/apache/incubator-apisix/issues/331)

### Plugins
- :sunrise: **[serverless](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/serverless.md)**: With serverless support, users can dynamically run any Lua function on a gateway node. Users can also use this feature as a lightweight plugin.[#86](https://github.com/apache/incubator-apisix/pull/86)
- :sunrise: **support IdP**: Support external authentication services, such as Auth0, okta, etc., users can use this to connect to Oauth2.0 and other authentication methods. [#447](https://github.com/apache/incubator-apisix/pull/447)
- [rate limit](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/limit-conn.md): Support for more restricted keys, such as `X-Forwarded-For` and `X-Real-IP`, and allows users to use Nginx variables, request headers, and request parameters as keys. [#228](https://github.com/apache/incubator-apisix/issues/228)
- [IP black and white list](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/ip-restriction.md) Support IP black and white list for security. [#398](https://github.com/apache/incubator-apisix/pull/398)

### CLI
- Add the `version` directive to get the version number of APISIX. [#420](https://github.com/apache/incubator-apisix/issues/420)

### Admin
- The `PATCH` API is supported and can be modified individually for a configuration without submitting the entire configuration. [#365](https://github.com/apache/incubator-apisix/pull/365)

### Dashboard
- :sunrise: **Add the online version of the dashboard**，users can [experience APISIX](http://apisix.iresty.com/) without install. [#374](https://github.com/apache/incubator-apisix/issues/374)


[Back to TOC](#table-of-contents)


## 0.6.0

> Released on 2019/08/05

This release brings many new features such as health check and circuit breaker, debug mode, opentracing and JWT auth. And add **built-in dashboard**.

### Core
- :sunrise: **[Health Check and Circuit Breaker](https://github.com/apache/incubator-apisix/blob/master/doc/health-check.md)**: Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability. [#249](https://github.com/apache/incubator-apisix/pull/249)
- Anti-ReDoS(Regular expression Denial of Service). [#252](https://github.com/apache/incubator-apisix/pull/250)
- supported debug mode. [#319](https://github.com/apache/incubator-apisix/pull/319)
- allowed to use different router. [#364](https://github.com/apache/incubator-apisix/pull/364)
- supported to match route by host + uri. [#325](https://github.com/apache/incubator-apisix/pull/325)
- allowed plugins to handler balance phase. [#299](https://github.com/apache/incubator-apisix/pull/299)
- added desc for upstream and service in schema. [#289](https://github.com/apache/incubator-apisix/pull/289)

### Plugins
- :sunrise: **[OpenTracing](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/zipkin.md)**: support Zipkin and Apache SkyWalking. [#304](https://github.com/apache/incubator-apisix/pull/304)
- [JWT auth](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/jwt-auth-cn.md). [#303](https://github.com/apache/incubator-apisix/pull/303)

### CLI
- support multiple ips of `allow`. [#340](https://github.com/apache/incubator-apisix/pull/340)
- supported real_ip configure in nginx.conf and added functions to get ip and remote ip. [#236](https://github.com/apache/incubator-apisix/pull/236)

### Dashboard
- :sunrise: **add built-in dashboard**. [#327](https://github.com/apache/incubator-apisix/pull/327)

### Test
- support OSX in Travis CI. [#217](https://github.com/apache/incubator-apisix/pull/217)
- installed all of the dependencies to `deps` folder. [#248](https://github.com/apache/incubator-apisix/pull/248)

[Back to TOC](#table-of-contents)
