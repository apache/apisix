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

- [1.2.0](#120)
- [1.1.0](#110)
- [1.0.0](#100)
- [0.9.0](#090)
- [0.8.0](#080)
- [0.7.0](#070)
- [0.6.0](#060)

## 1.2.0
1.2 版本在内核以及插件上带来了非常多的更新。

### Core
- :sunrise: **支持 etcd 集群**. [#1283](https://github.com/apache/incubator-apisix/pull/1283)
- 默认使用本地 DNS resolver, 这对于 k8s 环境更加友好. [#1387](https://github.com/apache/incubator-apisix/pull/1387)
- 支持在 `header_filter`、`body_filter` 和 `log` 阶段运行全局插件. [#1364](https://github.com/apache/incubator-apisix/pull/1364)
- 将目录 `lua/apisix` 修改为 `apisix`(**不向下兼容**). [#1351](https://github.com/apache/incubator-apisix/pull/1351)
- 增加 dashboard 子模块. [#1360](https://github.com/apache/incubator-apisix/pull/1360)
- 允许自定义共享字典. [#1367](https://github.com/apache/incubator-apisix/pull/1367)

### Plugin
- :sunrise: **新增 Apache Kafka 插件**. [#1312](https://github.com/apache/incubator-apisix/pull/1312)
- :sunrise: **新增 CORS 插件**. [#1327](https://github.com/apache/incubator-apisix/pull/1327)
- :sunrise: **新增 TCP logger 插件**. [#1221](https://github.com/apache/incubator-apisix/pull/1221)
- :sunrise: **新增 UDP logger 插件**. [1070](https://github.com/apache/incubator-apisix/pull/1070)
- :sunrise: **新增 proxy mirror 插件**. [#1288](https://github.com/apache/incubator-apisix/pull/1288)
- :sunrise: **新增 proxy cache 插件**. [#1153](https://github.com/apache/incubator-apisix/pull/1153)
- 在 proxy-rewrite 插件中废弃 websocket 开关(**不向下兼容**). [1332](https://github.com/apache/incubator-apisix/pull/1332)
-  OAuth 插件中增加基于公钥的自省支持. [#1266](https://github.com/apache/incubator-apisix/pull/1266)
- response-rewrite 插件通过 base64 来支持传输二进制数据. [#1381](https://github.com/apache/incubator-apisix/pull/1381)
- gRPC 转码插件支持 `deadline`. [#1149](https://github.com/apache/incubator-apisix/pull/1149)
- limit count 插件支持 redis 权限认证. [#1150](https://github.com/apache/incubator-apisix/pull/1150)
- Zipkin 插件支持名字和本地服务器 ip 的记录. [#1386](https://github.com/apache/incubator-apisix/pull/1386)
- Wolf-Rbac 插件增加 `change_pwd` 和 `user_info` 参数. [#1204](https://github.com/apache/incubator-apisix/pull/1204)

### Admin API
- :sunrise: 对调用 Admin API 增加 key-auth 权限认证(**not backward compatible**). [#1169](https://github.com/apache/incubator-apisix/pull/1169)
- 隐藏 SSL 私钥的返回值. [#1240](https://github.com/apache/incubator-apisix/pull/1240)

### Bugfix
- 在复用 table 之前遗漏了对数据的清理 (**会引发内存泄漏**). [#1134](https://github.com/apache/incubator-apisix/pull/1134)
- 如果 yaml 中路由非法就打印警告信息. [#1141](https://github.com/apache/incubator-apisix/pull/1141)
- 使用空字符串替代空的 balancer IP. [#1166](https://github.com/apache/incubator-apisix/pull/1166)
- 修改 node-status 和 heartbeat 插件没有 schema 的问题. [#1249](https://github.com/apache/incubator-apisix/pull/1249)
- basic-auth 增加 required 字段. [#1251](https://github.com/apache/incubator-apisix/pull/1251)
- 检查上游合法节点的个数. [#1292](https://github.com/apache/incubator-apisix/pull/1292)


## 1.1.0

这个版本主要是加强代码的稳定性，以及增加更多的文档。

### Core
- 每次跑测试用例都指定 perl 包含路径。 [#1097](https://github.com/apache/incubator-apisix/pull/1097)
- 增加对代理协议的支持。 [#1113](https://github.com/apache/incubator-apisix/pull/1113)
- 增加用于校验 nginx.conf 的命令。 [#1112](https://github.com/apache/incubator-apisix/pull/1112)
- 支持「nginx 最多可以打开文件数」可配置，并增大其默认配置。[#1105](https://github.com/apache/incubator-apisix/pull/1105) [#1098](https://github.com/apache/incubator-apisix/pull/1098)
- 优化日志模块。 [#1093](https://github.com/apache/incubator-apisix/pull/1093)
- 支持 SO_REUSEPORT 。 [#1085](https://github.com/apache/incubator-apisix/pull/1085)

### Doc
- 增加 Grafana 元数据下载链接. [#1119](https://github.com/apache/incubator-apisix/pull/1119)
- 更新 README.md。 [#1118](https://github.com/apache/incubator-apisix/pull/1118)
- 增加 wolf-rbac 插件说明文档 [#1116](https://github.com/apache/incubator-apisix/pull/1116)
- 更新 rpm 下载链接。 [#1108](https://github.com/apache/incubator-apisix/pull/1108)
- 增加更多英文文章链接。 [#1092](https://github.com/apache/incubator-apisix/pull/1092)
- 增加文档贡献指引。 [#1086](https://github.com/apache/incubator-apisix/pull/1086)
- 检查更新「快速上手」文档。 [#1084](https://github.com/apache/incubator-apisix/pull/1084)
- 检查更新「插件开发指南」。 [#1078](https://github.com/apache/incubator-apisix/pull/1078)
- 更新 admin-api-cn.md 。 [#1067](https://github.com/apache/incubator-apisix/pull/1067)
- 更新 architecture-design-cn.md 。 [#1065](https://github.com/apache/incubator-apisix/pull/1065)

### CI
- 移除不再必须的补丁。 [#1090](https://github.com/apache/incubator-apisix/pull/1090)
- 修复使用 luarocks 安装时路径错误问题。[#1068](https://github.com/apache/incubator-apisix/pull/1068)
- 为 luarocks 安装专门配置一个 travis 进行回归测试。 [#1063](https://github.com/apache/incubator-apisix/pull/1063)

### Plugins
- 「节点状态」插件使用 nginx 内部请求替换原来的外部请求。 [#1109](https://github.com/apache/incubator-apisix/pull/1109)
- 增加 wolf-rbac 插件。 [#1095](https://github.com/apache/incubator-apisix/pull/1095)
- 增加 udp-logger 插件。 [#1070](https://github.com/apache/incubator-apisix/pull/1070)


## 1.0.0

这个版本主要是加强代码的稳定性，以及增加更多的文档。

### Core
- :sunrise: 支持路由的优先级。可以在 URI 相同的条件下，根据 header、args、优先级等条件，来匹配到不同的上游服务。 [#998](https://github.com/apache/incubator-apisix/pull/998)
- 在没有匹配到任何路由的时候，返回错误信息。以便和其他的 404 请求区分开。[#1013](https://github.com/apache/incubator-apisix/pull/1013)
- dashboard 的地址 `/apisix/admin` 支持 CORS。[#982](https://github.com/apache/incubator-apisix/pull/982)
- jsonschema 校验器返回更清晰的错误提示。[#1011](https://github.com/apache/incubator-apisix/pull/1011)
- 升级 `ngx_var` 模块到 0.5 版本。[#1005](https://github.com/apache/incubator-apisix/pull/1005)
- 升级 `lua-resty-etcd` 模块到 0.8 版本。[#980](https://github.com/apache/incubator-apisix/pull/980)
- 在开发模式下，自动把 worker 数调整为 1。[#926](https://github.com/apache/incubator-apisix/pull/926)
- 从代码仓库中移除 nginx.conf 文件，它每次都会自动生成，不可手工修改。[#974](https://github.com/apache/incubator-apisix/pull/974)

### Doc
- 增加如何自定义开发插件的文档。[#909](https://github.com/apache/incubator-apisix/pull/909)
- 修复 serverless 插件文档中错误的示例。[#1006](https://github.com/apache/incubator-apisix/pull/1006)
- 增加 Oauth 插件的使用文档。[#987](https://github.com/apache/incubator-apisix/pull/987)
- 增加 dashboard 编译的文档。[#985](https://github.com/apache/incubator-apisix/pull/985)
- 增加如何进行 a/b 测试的文档。[#957](https://github.com/apache/incubator-apisix/pull/957)
- 增加如何开启 MQTT 插件的文档。[#916](https://github.com/apache/incubator-apisix/pull/916)

### Test case
- 增加 key-auth 插件正常情况下的测试案例。[#964](https://github.com/apache/incubator-apisix/pull/964/)
- 增加 grpc transcode pb 选项的测试。[#920](https://github.com/apache/incubator-apisix/pull/920)

## 0.9.0

这个版本带来很多新特性，比如支持使用 Tengine 运行 APISIX，增加了对开发人员更友好的高级调试模式，还有新的URI重定向插件等。

### Core
- :sunrise: 支持使用 Tengine 运行 APISIX。 [#683](https://github.com/apache/incubator-apisix/pull/683)
- :sunrise: 启用 HTTP2 并支持设置 ssl_protocols。 [#663](https://github.com/apache/incubator-apisix/pull/663)
- :sunrise: 增加高级调试模式，可在不重启的服务的情况下动态打印指定模块方法的请求参数或返回值。[#614](https://github.com/apache/incubator-apisix/pull/641)
- 安装程序增加了仪表盘开关，支持用户自主选择是否安装仪表板程序。 [#686](https://github.com/apache/incubator-apisix/pull/686)
- 取消对 R3 路由的支持，并移除 R3 路由模块。 [#725](https://github.com/apache/incubator-apisix/pull/725)


### Plugins
- :sunrise: **[Redirect URI](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/redirect.md)**： URI 重定向插件。 [#732](https://github.com/apache/incubator-apisix/pull/732)
- [Proxy Rewrite](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/proxy-rewrite.md)：支持 `header` 删除功能。 [#658](https://github.com/apache/incubator-apisix/pull/658)
- [Limit Count](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/limit-count.md)： 通过 `Redis Server` 聚合 `APISIX` 节点之间将共享流量限速结果，实现集群流量限速。[#624](https://github.com/apache/incubator-apisix/pull/624)

### lua-resty-*
- lua-resty-radixtree
    - 支持将`host + uri`作为索引。
- lua-resty-jsonschema
    - 该扩展作用是JSON数据验证器，用于替换现有的 `lua-rapidjson` 扩展。

### Bugfix
- 在多个使用者的情况下，`key-auth` 插件无法正确运行。 [#826](https://github.com/apache/incubator-apisix/pull/826)
- 无法在 `API Server` 中获取 `serverless`插件配置。 [#787](https://github.com/apache/incubator-apisix/pull/787)
- 解决使用 `proxy-write` 重写URI时GET参数丢失问题。 [#642](https://github.com/apache/incubator-apisix/pull/642)
- `Zipkin` 插件未将跟踪数据设置为请求头. [#715](https://github.com/apache/incubator-apisix/pull/715)
- 使用本地文件作为配置中心时，跳过 etcd 初始化。 [#737](https://github.com/apache/incubator-apisix/pull/737)
- 在APISIX CLI中跳过 luajit 环境的`check cjson`。[#652](https://github.com/apache/incubator-apisix/pull/652)
- 配置 `Upstream` 时，选择 `balancer` 类型为 `chash` 时，支持更多Nginx内置变量作为计算key。 [#775](https://github.com/apache/incubator-apisix/pull/775)


### Dependencies
- 使用 `lua-resty-jsonschema` 全局替换 `lua-rapidjson` 扩展，`lua-resty-jsonschema` 解析速度更快，更容易编译。


## 0.8.0
> Released on 2019/09/30

这个版本带来很多新的特性，比如四层协议的代理, 支持 MQTT 协议代理，以及对 ARM 平台的支持, 和代理改写插件等。

### Core
- :sunrise: **[增加单机模式](https://github.com/apache/incubator-apisix/blob/master/doc/stand-alone-cn.md)**: 使用 yaml 配置文件来更新 APISIX 的配置，这对于 kubernetes 更加友好。 [#464](https://github.com/apache/incubator-apisix/pull/464)
- :sunrise: **[支持 stream 代理](https://github.com/apache/incubator-apisix/blob/master/doc/stream-proxy-cn.md)**. [#513](https://github.com/apache/incubator-apisix/pull/513)
- :sunrise: 支持[在 consumer 上绑定插件](https://github.com/apache/incubator-apisix/blob/master/doc/architecture-design-cn.md#consumer). [#544](https://github.com/apache/incubator-apisix/pull/544)
- 上游增加对域名的支持，而不仅是 IP。[#522](https://github.com/apache/incubator-apisix/pull/522)
- 当上游节点的权重为 0 时自动忽略。[#536](https://github.com/apache/incubator-apisix/pull/536)

### Plugins
- :sunrise: **[MQTT 代理](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/mqtt-proxy-cn.md)**: 支持用 `client_id` 对 MQTT 进行负载均衡，同时支持 MQTT 3.1 和 5.0 两个协议标准。 [#513](https://github.com/apache/incubator-apisix/pull/513)
- [proxy-rewrite](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/proxy-rewrite.md): 对代理到上游的请求进行改写，包括 host, uri 和 schema。 [#594](https://github.com/apache/incubator-apisix/pull/594)

### ARM
- :sunrise: **APISIX 可以在基于 ARM64 架构的 Ubuntu 18.04 系统中正常运行**, 搭配上 MQTT 插件，你可以把它当做 IoT 网关来使用。

### lua-resty-*
- lua-resty-ipmatcher
    - 支持 IPv6。
    - 支持 IP 黑白名单和路由。
- lua-resty-radixtree
    - 允许指定多个 host, remote_addr 和 uri。
    - 允许设置用户自定义函数来做额外的过滤。
    - 使用 `lua-resty-ipmatcher` 替代 `lua-resty-iputils`, `lua-resty-ipmatcher` 支持 IPv6 并且速度更快。


### Bugfix
- 健康检查: 修复在多 worker 下运行时健康检查 checker 的名字错误。 [#568](https://github.com/apache/incubator-apisix/issues/568)

### Dependencies
- 把 `lua-tinyyaml` 从源码中移除，通过 Luarocks 来安装。

## 0.7.0

> Released on 2019/09/06

这个版本带来很多新的特性，比如 IP 黑白名单、gPRC 协议转换、支持 IPv6、对接 IdP（身份认证提供商）服务、serverless、默认路由修改为radix tree（**不向下兼容**）等。

### Core
- :sunrise: **[gRPC 协议转换](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/grpc-transcoding-cn.md)**: 支持 gRPC 协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API. [#395](https://github.com/apache/incubator-apisix/issues/395)
- :sunrise: **[radix tree 路由](https://github.com/apache/incubator-apisix/blob/master/doc/router-radixtree.md)**: 默认的路由器更改为 radix tree，支持把 uri、host、cookie、请求头、请求参数、Nginx 内置变量等作为路由的条件，并支持等于、大于、小于等常见操作符，更加强大和灵活. **需要注意的是，这个改动不向下兼容，所有使用历史版本的用户，需要手动修改路由才能正常使用**。[#414](https://github.com/apache/incubator-apisix/issues/414)
- 动态上游支持更多的参数，可以指定上游的 uri 和 host，以及是否开启 websocket. [#451](https://github.com/apache/incubator-apisix/pull/451)
- 支持从 `ctx.var` 中直接获取 cookie 中的值. [#449](https://github.com/apache/incubator-apisix/pull/449)
- 路由支持 IPv6. [#331](https://github.com/apache/incubator-apisix/issues/331)

### Plugins
- :sunrise: **[serverless](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/serverless-cn.md)**: 支持 serverless，用户可以把任意 Lua 函数动态的在网关节点上运行。用户也可以把这个功能当做是轻量级的插件来使用。[#86](https://github.com/apache/incubator-apisix/pull/86)
- :sunrise: **IdP 支持**: 支持外部的身份认证服务，比如 Auth0，okta 等，用户可以借此来对接 Oauth2.0 等认证方式。 [#447](https://github.com/apache/incubator-apisix/pull/447)
- [限流限速](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/limit-conn-cn.md)支持更多的限制 key，比如 X-Forwarded-For 和 X-Real-IP，并且允许用户把 Nginx 变量、请求头和请求参数作为 key. [#228](https://github.com/apache/incubator-apisix/issues/228)
- [IP 黑白名单](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/ip-restriction.md) 支持 IP 黑白名单，提供更高的安全性。[#398](https://github.com/apache/incubator-apisix/pull/398)

### CLI
- 增加 `version` 指令，获取 APISIX 的版本号. [#420](https://github.com/apache/incubator-apisix/issues/420)

### Admin
- 支持 `PATCH` API，可以针对某个配置单独修改，而不再用提交整段配置。[#365](https://github.com/apache/incubator-apisix/pull/365)

### Dashboard
- :sunrise: **增加在线版本的 dashboard**，用户不用安装即可[体验 APISIX](http://apisix.iresty.com/). [#374](https://github.com/apache/incubator-apisix/issues/374)


[Back to TOC](#table-of-contents)


## 0.6.0

> Released on 2019/08/05

这个版本带来很多新的特性，比如健康检查、服务熔断、debug 模式，分布式追踪、JWT
认证等，以及**内置的 dashboard**.

### Core
- :sunrise: **[健康检查和服务熔断](https://github.com/apache/incubator-apisix/blob/master/doc/health-check.md)**: 对上游节点开启健康检查，智能判断服务状态进行熔断和连接. [#249](https://github.com/apache/incubator-apisix/pull/249)
- 阻止ReDoS(Regular expression Denial of Service). [#252](https://github.com/apache/incubator-apisix/pull/250)
- 支持 debug 模式. [#319](https://github.com/apache/incubator-apisix/pull/319)
- 允许自定义路由. [#364](https://github.com/apache/incubator-apisix/pull/364)
- 路由支持 host 和 uri 的组合. [#325](https://github.com/apache/incubator-apisix/pull/325)
- 允许在 balance 阶段注入插件. [#299](https://github.com/apache/incubator-apisix/pull/299)
- 为 upstream 和 service 在 schema 中增加描述信息. [#289](https://github.com/apache/incubator-apisix/pull/289)

### Plugins
- :sunrise: **[分布式追踪 OpenTracing](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/zipkin.md)**: 支持 Zipkin 和 Apache SkyWalking. [#304](https://github.com/apache/incubator-apisix/pull/304)
- [JWT 认证](https://github.com/apache/incubator-apisix/blob/master/doc/plugins/jwt-auth-cn.md). [#303](https://github.com/apache/incubator-apisix/pull/303)

### CLI
- `allow` 指令中支持多个 ip 地址. [#340](https://github.com/apache/incubator-apisix/pull/340)
- 支持在 nginx.conf 中配置 real_ip 指令，以及增加函数来获取 ip. [#236](https://github.com/apache/incubator-apisix/pull/236)

### Dashboard
- :sunrise: **增加内置的 dashboard**. [#327](https://github.com/apache/incubator-apisix/pull/327)

### Test
- 在 Travis CI 中支持 OSX. [#217](https://github.com/apache/incubator-apisix/pull/217)
- 把所有依赖安装到 `deps` 目录. [#248](https://github.com/apache/incubator-apisix/pull/248)

[Back to TOC](#table-of-contents)
