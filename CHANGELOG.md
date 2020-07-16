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

- [1.4.0](#140)
- [1.3.0](#130)
- [1.2.0](#120)
- [1.1.0](#110)
- [1.0.0](#100)
- [0.9.0](#090)
- [0.8.0](#080)
- [0.7.0](#070)
- [0.6.0](#060)

## 1.4.0

### Core
- Admin API: Support unique names for routes [1655](https://github.com/apache/incubator-apisix/pull/1655)
- Optimization of log buffer size and flush time [1570](https://github.com/apache/incubator-apisix/pull/1570)

### New plugins
- :sunrise: **Apache Skywalking plugin** [1241](https://github.com/apache/incubator-apisix/pull/1241)
- :sunrise: **Keycloak Identity Server Plugin** [1701](https://github.com/apache/incubator-apisix/pull/1701)
- :sunrise: **Echo Plugin** [1632](https://github.com/apache/incubator-apisix/pull/1632)
- :sunrise: **Consume Restriction Plugin** [1437](https://github.com/apache/incubator-apisix/pull/1437)

### Improvements
- Batch Request : Copy all headers to every request [1697](https://github.com/apache/incubator-apisix/pull/1697)
- SSL private key encryption [1678](https://github.com/apache/incubator-apisix/pull/1678)
- Improvement of docs for multiple plugins


## 1.3.0

The 1.3 version is mainly for security update.

### Security
- reject invalid header[#1462](https://github.com/apache/incubator-apisix/pull/1462) and uri safe encode[#1461](https://github.com/apache/incubator-apisix/pull/1461)
- only allow 127.0.0.1 access admin API and dashboard by default. [#1458](https://github.com/apache/incubator-apisix/pull/1458)

### Plugin
- :sunrise: **add batch request plugin**. [#1388](https://github.com/apache/incubator-apisix/pull/1388)
- implemented plugin `sys logger`. [#1414](https://github.com/apache/incubator-apisix/pull/1414)


## 1.2.0

The 1.2 version brings many new features, including core and plugins.

### Core
- :sunrise: **support etcd cluster**. [#1283](https://github.com/apache/incubator-apisix/pull/1283)
- using the local DNS resolver by default, which is friendly for k8s. [#1387](https://github.com/apache/incubator-apisix/pull/1387)
- support to run `header_filter`, `body_filter` and `log` phases for global rules. [#1364](https://github.com/apache/incubator-apisix/pull/1364)
- changed the `lua/apisix` dir to `apisix`(**not backward compatible**). [#1351](https://github.com/apache/incubator-apisix/pull/1351)
- add dashboard as submodule. [#1360](https://github.com/apache/incubator-apisix/pull/1360)
- allow adding custom shared dict. [#1367](https://github.com/apache/incubator-apisix/pull/1367)

### Plugin
- :sunrise: **add Apache Kafka plugin**. [#1312](https://github.com/apache/incubator-apisix/pull/1312)
- :sunrise: **add CORS plugin**. [#1327](https://github.com/apache/incubator-apisix/pull/1327)
- :sunrise: **add TCP logger plugin**. [#1221](https://github.com/apache/incubator-apisix/pull/1221)
- :sunrise: **add UDP logger plugin**. [1070](https://github.com/apache/incubator-apisix/pull/1070)
- :sunrise: **add proxy mirror plugin**. [#1288](https://github.com/apache/incubator-apisix/pull/1288)
- :sunrise: **add proxy cache plugin**. [#1153](https://github.com/apache/incubator-apisix/pull/1153)
- drop websocket enable control in proxy-rewrite plugin(**not backward compatible**). [1332](https://github.com/apache/incubator-apisix/pull/1332)
- Adding support to public key based introspection for OAuth plugin. [#1266](https://github.com/apache/incubator-apisix/pull/1266)
- response-rewrite plugin support binary data to client by base64. [#1381](https://github.com/apache/incubator-apisix/pull/1381)
- plugin `grpc-transcode` supports grpc deadline. [#1149](https://github.com/apache/incubator-apisix/pull/1149)
- support password auth for limit-count-redis. [#1150](https://github.com/apache/incubator-apisix/pull/1150)
- Zipkin plugin add service name and report local server IP. [#1386](https://github.com/apache/incubator-apisix/pull/1386)
- add `change_pwd` and `user_info` for Wolf-Rbac plugin. [#1204](https://github.com/apache/incubator-apisix/pull/1204)

### Admin API
- :sunrise: support key-based authentication for Admin API(**not backward compatible**). [#1169](https://github.com/apache/incubator-apisix/pull/1169)
- hide SSL private key in admin API. [#1240](https://github.com/apache/incubator-apisix/pull/1240)

### Bugfix
- missing `clear` table before to reuse table (**will cause memory leak**). [#1134](https://github.com/apache/incubator-apisix/pull/1134)
- print warning error message if the yaml route file is invalid. [#1141](https://github.com/apache/incubator-apisix/pull/1141)
- the balancer IP may be nil, use an empty string instead. [#1166](https://github.com/apache/incubator-apisix/pull/1166)
- plugin node-status and heartbeat don't have schema. [#1249](https://github.com/apache/incubator-apisix/pull/1249)
- the plugin basic-auth needs required field. [#1251](https://github.com/apache/incubator-apisix/pull/1251)
- check the count of upstream valid node. [#1292](https://github.com/apache/incubator-apisix/pull/1292)


## 1.1.0

This release is mainly to strengthen the stability of the code and add more documentation.

### Core

- always specify perl include path when runing test cases. [#1097](https://github.com/apache/incubator-apisix/pull/1097)
- Feature: Add support for PROXY Protocol. [#1113](https://github.com/apache/incubator-apisix/pull/1113)
- enhancement: add verify command to verify apisix configuration(nginx.conf). [#1112](https://github.com/apache/incubator-apisix/pull/1112)
- feature: increase the default size of the core file. [#1105](https://github.com/apache/incubator-apisix/pull/1105)
- feature: make the number of file is as configurable as the connections. [#1098](https://github.com/apache/incubator-apisix/pull/1098)
- core: improve the core.log module. [#1093](https://github.com/apache/incubator-apisix/pull/1093)
- Modify bin/apisix to support the SO_REUSEPORT. [#1085](https://github.com/apache/incubator-apisix/pull/1085)

### Doc

- doc: add link to download grafana meta data. [#1119](https://github.com/apache/incubator-apisix/pull/1119)
- doc: Update README.md. [#1118](https://github.com/apache/incubator-apisix/pull/1118)
- doc: doc: add wolf-rbac plugin. [#1116](https://github.com/apache/incubator-apisix/pull/1116)
- doc: update the download link of rpm. [#1108](https://github.com/apache/incubator-apisix/pull/1108)
- doc: add more english article. [#1092](https://github.com/apache/incubator-apisix/pull/1092)
- Adding contribution guidelines for the documentation. [#1086](https://github.com/apache/incubator-apisix/pull/1086)
- doc: getting-started.md check. [#1084](https://github.com/apache/incubator-apisix/pull/1084)
- Added additional information and refactoring sentences. [#1078](https://github.com/apache/incubator-apisix/pull/1078)
- Update admin-api-cn.md. [#1067](https://github.com/apache/incubator-apisix/pull/1067)
- Update architecture-design-cn.md. [#1065](https://github.com/apache/incubator-apisix/pull/1065)

### CI

- ci: remove patch which is no longer necessary and removed in the upst. [#1090](https://github.com/apache/incubator-apisix/pull/1090)
- fix path error when install with luarocks. [#1068](https://github.com/apache/incubator-apisix/pull/1068)
- travis: run a apisix instance which intalled by luarocks. [#1063](https://github.com/apache/incubator-apisix/pull/1063)

### Plugins

- feature: Add wolf rbac plugin. [#1095](https://github.com/apache/incubator-apisix/pull/1095)
- Adding UDP logger plugin. [#1070](https://github.com/apache/incubator-apisix/pull/1070)
- enhancement: using internal request instead of external request in node-status plugin. [#1109](https://github.com/apache/incubator-apisix/pull/1109)

## 1.0.0

This release is mainly to strengthen the stability of the code and add more documentation.

### Core

- :sunrise: Support routing priority. You can match different upstream services based on conditions such as header, args, priority, etc. under the same URI. [#998](https://github.com/apache/incubator-apisix/pull/998)
- When no route is matched, an error message is returned. To distinguish it from other 404 requests. [#1013](https://github.com/apache/incubator-apisix/pull/1013)
- The address of the dashboard `/apisix/admin` supports CORS. [#982](https://github.com/apache/incubator-apisix/pull/982)
- The jsonschema validator returns a clearer error message. [#1011](https://github.com/apache/incubator-apisix/pull/1011)
- Upgrade the `ngx_var` module to version 0.5. [#1005](https://github.com/apache/incubator-apisix/pull/1005)
- Upgrade the `lua-resty-etcd` module to version 0.8. [#980](https://github.com/apache/incubator-apisix/pull/980)
- In development mode, the number of workers is automatically adjusted to 1. [#926](https://github.com/apache/incubator-apisix/pull/926)
- Remove the nginx.conf file from the code repository. It is automatically generated every time and cannot be modified manually. [#974](https://github.com/apache/incubator-apisix/pull/974)

### Doc

- Added documentation on how to customize development plugins. [#909](https://github.com/apache/incubator-apisix/pull/909)
- fixed example's bugs in the serverless plugin documentation. [#1006](https://github.com/apache/incubator-apisix/pull/1006)
- Added documentation for using the Oauth plugin. [#987](https://github.com/apache/incubator-apisix/pull/987)
- Added dashboard compiled documentation. [#985](https://github.com/apache/incubator-apisix/pull/985)
- Added documentation on how to perform a/b testing. [#957](https://github.com/apache/incubator-apisix/pull/957)
- Added documentation on how to enable the MQTT plugin. [#916](https://github.com/apache/incubator-apisix/pull/916)

### Test case

- Add test cases for key-auth plugin under normal circumstances. [#964](https://github.com/apache/incubator-apisix/pull/964/)
- Added tests for gRPC transcode pb options. [#920](https://github.com/apache/incubator-apisix/pull/920)

## 0.9.0

This release brings many new features, such as support for running APISIX with Tengine,
an advanced debugging mode that is more developer friendly, and a new URI redirection plugin.

### Core

- :sunrise: Supported to run APISIX with tengine. [#683](https://github.com/apache/incubator-apisix/pull/683)
- :sunrise: Enabled HTTP2 and supported to set ssl_protocols. [#663](https://github.com/apache/incubator-apisix/pull/663)
- :sunrise: Advanced Debug Mode, Target module function's input arguments or returned value would be printed once this option is enabled. [#614](https://github.com/apache/incubator-apisix/pull/641)
- Support to install APISIX without dashboard. [#686](https://github.com/apache/incubator-apisix/pull/686)
- Removed router R3 [#725](https://github.com/apache/incubator-apisix/pull/725)

### Plugins

- [Redirect URI](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/redirect.md): Redirect URI plugin. [#732](https://github.com/apache/incubator-apisix/pull/732)
- [Proxy Rewrite](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/proxy-rewrite.md): Supported remove `header` feature. [#658](https://github.com/apache/incubator-apisix/pull/658)
- [Limit Count](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/limit-count.md): Supported global limit count with `Redis Server`.[#624](https://github.com/apache/incubator-apisix/pull/624)

### lua-resty-*

- lua-resty-radixtree
  - Support for `host + uri` as an index.
- lua-resty-jsonschema
  - This extension is a JSON data validator that replaces the existing `lua-rapidjson` extension.

### Bugfix

- key-auth plugin cannot run accurately in the case of multiple consumers. [#826](https://github.com/apache/incubator-apisix/pull/826)
- Exported schema for plugin serverless. [#787](https://github.com/apache/incubator-apisix/pull/787)
- Discard args of uri when using proxy-write plugin [#642](https://github.com/apache/incubator-apisix/pull/642)
- Zipkin plugin not set tracing data to request header. [#715](https://github.com/apache/incubator-apisix/pull/715)
- Skipped check cjson for luajit environment in apisix CLI. [#652](https://github.com/apache/incubator-apisix/pull/652)
- Skipped to init etcd if use local file as config center. [#737](https://github.com/apache/incubator-apisix/pull/737)
- Support more built-in parameters when set chash balancer. [#775](https://github.com/apache/incubator-apisix/pull/775)

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
