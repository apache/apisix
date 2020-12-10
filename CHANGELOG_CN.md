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

- [2.1.0](#210)
- [2.0.0](#200)
- [1.5.0](#150)
- [1.4.1](#141)
- [1.4.0](#140)
- [1.3.0](#130)
- [1.2.0](#120)
- [1.1.0](#110)
- [1.0.0](#100)
- [0.9.0](#090)
- [0.8.0](#080)
- [0.7.0](#070)
- [0.6.0](#060)


## 2.1.0

### Core
- :sunrise: **支持使用环境变量来配置参数.** [#2743](https://github.com/apache/apisix/pull/2743)
- :sunrise: **支持使用 TLS 来连接 etcd.** [#2548](https://github.com/apache/apisix/pull/2548)
- 自动生成对象的创建和更新时间. [#2740](https://github.com/apache/apisix/pull/2740)
- 在上游中开启 websocket 时，增加日志来提示此功能即将废弃.[#2691](https://github.com/apache/apisix/pull/2691)
- 增加日志来提示 consumer id 即将废弃.[#2829](https://github.com/apache/apisix/pull/2829)
- 增加 `X-APISIX-Upstream-Status` 头来区分 5xx 错误来自上游还是 APISIX 自身。[#2817](https://github.com/apache/apisix/pull/2817)
- 支持 Nginx 配置片段。[#2803](https://github.com/apache/apisix/pull/2803)

## Plugin
- :sunrise: **升级协议来 Apache Skywalking 8.0**[#2389](https://github.com/apache/apisix/pull/2389). 这个版本只支持 skywalking 8.0 协议。此插件默认关闭，需要修改 config.yaml 来开启。这是不向下兼容的修改。
- :sunrise: 新增阿里云 sls 日志服务插件。[#2169](https://github.com/apache/apisix/issues/2169)
- proxy-cache: cache_zone 字段改为可选.[#2776](https://github.com/apache/apisix/pull/2776)
- 在数据平面校验插件的配置。[#2856](https://github.com/apache/apisix/pull/2856)

## Bugfix
- :bug: fix(etcd): 处理 etcd compaction.[#2687](https://github.com/apache/apisix/pull/2687)
- 将 `conf/cert` 中的测试证书移动到 `t/certs` 目录中，并且默认关闭 SSL。这是不向下兼容的修改。 [#2112](https://github.com/apache/apisix/pull/2112)
- 检查 decrypt key 来阻止 lua thread 中断。 [#2815](https://github.com/apache/apisix/pull/2815)

## 不向下兼容特性预告
- 在 2.3 发布版本中，consumer 将只支持用户名，废弃 id，consumer需要在 etcd 中手工清理掉 id 字段，不然使用时 schema 校验会报错
- 在 2.3 发布版本中，将不再支持在 upstream 上开启 websocket
- 在 3.0 版本中，数据平面和控制平面将分开为两个独立的端口，即现在的 9080 端口将只处理数据平面的请求，不再处理 admin API 的请求

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/8)

## 2.0.0

这是一个 release candidate。

### Core
- :sunrise: **从 etcd v2 协议迁移到 v3，这是不向下兼容的修改。Apache APISIX 只支持 etcd 3.4 以及后续的版本。** [#2036](https://github.com/apache/apisix/pull/2036)
- 支持为上游对象增加标签。[#2279](https://github.com/apache/apisix/pull/2279)
- 为上游、路由等资源增加更多字段，比如 create_time 和 update_time。[#2444](https://github.com/apache/apisix/pull/2444)
- 使用拦截器来保护插件的路由。[#2416](https://github.com/apache/apisix/pull/2416)
- 支持 http 和 https 监听多个端口。[#2409](https://github.com/apache/apisix/pull/2409)
- 实现 `core.sleep` 函数。[#2397](https://github.com/apache/apisix/pull/2397)

## Plugin
- :sunrise: **增加 AK/SK(HMAC) 认证插件。**[#2192](https://github.com/apache/apisix/pull/2192)
- :sunrise: 增加 referer-restriction 插件。[#2352](https://github.com/apache/apisix/pull/2352)
- `limit-count` 插件支持 `redis` cluster。[#2406](https://github.com/apache/apisix/pull/2406)
- proxy-cache 插件支持存储临时文件。[#2317](https://github.com/apache/apisix/pull/2317)
- http-logger 插件支持通过 admin API 来指定文件格式。[#2309](https://github.com/apache/apisix/pull/2309)

## Bugfix
- :bug: **`高优先级`** 当数据平面接收到删除某一个资源(路由、上游等)的指令时，没有正确的清理缓存，导致存在的资源也会找不到。这个问题在长时间、频繁删除操作的情况下才会出现。[#2168](https://github.com/apache/apisix/pull/2168)
- 修复路由优先级不生效的问题。[#2447](https://github.com/apache/apisix/pull/2447)
- 在 `init_worker` 阶段设置随机数, 而不是 `init` 阶段。[#2357](https://github.com/apache/apisix/pull/2357)
- 删除 jwt 插件中不支持的算法。[#2356](https://github.com/apache/apisix/pull/2356)
- 当重定向插件的 `http_to_https` 开启时，返回正确的响应码。[#2311](https://github.com/apache/apisix/pull/2311)

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/7)

## CVE
- 修复 Admin API 默认访问令牌漏洞

## 1.5.0

### Core
- Admin API：支持使用SSL证书进行身份验证。[1747](https://github.com/apache/apisix/pull/1747)
- Admin API：同时支持标准的PATCH和子路径PATCH。[1930](https://github.com/apache/apisix/pull/1930)
- HealthCheck：支持自定义检查端口。[1914](https://github.com/apache/apisix/pull/1914)
- Upstream：支持禁用 `Nginx` 默认重试机制。[1919](https://github.com/apache/apisix/pull/1919)
- URI：支持以配置方式删除 `URI` 末尾的 `/` 符号。[1766](https://github.com/apache/apisix/pull/1766)

### New Plugin
- :sunrise: **新增 请求验证器 插件** [1709](https://github.com/apache/apisix/pull/1709)

### Improvements
- 变更：nginx `worker_shutdown_timeout` 配置默认值由 `3s` 变更为推荐值 `240s`。[1883](https://github.com/apache/apisix/pull/1883)
- 变更：`healthcheck` 超时时间类型 由 `integer ` 变更为 `number`。[1892](https://github.com/apache/apisix/pull/1892)
- 变更：`request-validation` 插件输入参数支持 `JsonSchema` 验证。[1920](https://github.com/apache/apisix/pull/1920)
- 变更：为 Makefile `install` 命令添加注释。[1912](https://github.com/apache/apisix/pull/1912)
- 变更：更新 config.yaml `etcd.timeout` 默认配置的注释。[1929](https://github.com/apache/apisix/pull/1929)
- 变更：为 `prometheus` 添加更多度量指标，以更好地了解 `APISIX` 节点的情况。[1888](https://github.com/apache/apisix/pull/1888)
- 变更：为 `cors` 插件添加更多配置选项。[1963](https://github.com/apache/apisix/pull/1963)

### Bugfix
- 修复：`healthcheck` 获取 `host` 配置失败。 [1871](https://github.com/apache/apisix/pull/1871)
- 修复：插件运行时数据保存到 `etcd`。 [1910](https://github.com/apache/apisix/pull/1910)
- 修复：多次运行 `apisix start` 将启动多个 `Nginx` 进程。[1913](https://github.com/apache/apisix/pull/1913)
- 修复：从临时文件读取请求正文（如果已缓存）。[1863](https://github.com/apache/apisix/pull/1863)
- 修复：批处理器名称和错误返回类型。[1927](https://github.com/apache/apisix/pull/1927)
- 修复：`limit-count` 插件 `redis.ttl` 读取异常。[1928](https://github.com/apache/apisix/pull/1928)
- 修复：被动健康检查不能提供健康报告。[1918](https://github.com/apache/apisix/pull/1918)
- 修复：避免插件中直接修改或使用原始配置数据。[1958](https://github.com/apache/apisix/pull/1958)
- 修复：`invalid-upstream` 测试用例稳定性问题。[1925](https://github.com/apache/apisix/pull/1925)

### Doc
- 文档：添加 `APISIX Lua` 代码风格指南。[1874](https://github.com/apache/apisix/pull/1874)
- 文档：修正 `README` 中语法错误。[1894](https://github.com/apache/apisix/pull/1894)
- 文档：修正 `benchmark` 文档中图片链接错误。[1896](https://github.com/apache/apisix/pull/1896)
- 文档：修正 `FAQ`、`admin-api`、`architecture-design`、`discovery`、`prometheus`、`proxy-rewrite`、`redirect`、`http-logger` 文档中错别字。[1916](https://github.com/apache/apisix/pull/1916)
- 文档：更新 `request-validation` 插件示例。[1926](https://github.com/apache/apisix/pull/1926)
- 文档：修正 `architecture-design` 文档中错别字。[1938](https://github.com/apache/apisix/pull/1938)
- 文档：添加 `how-to-build` 文档中在 `Linux` 和 `macOS` 系统中单元测试 `Nginx` 的默认引入路径。[1936](https://github.com/apache/apisix/pull/1936)
- 文档：添加 `request-validation` 插件中文文档。[1932](https://github.com/apache/apisix/pull/1932)
- 文档：修正 `README` 中 `gRPC transcoding` 文档路径。[1945](https://github.com/apache/apisix/pull/1945)
- 文档：修正 `README` 中 `uri-blocker` 文档路径。[1950](https://github.com/apache/apisix/pull/1950)
- 文档：修正 `README` 中 `grpc-transcode` 文档路径。[1946](https://github.com/apache/apisix/pull/1946)
- 文档: 删除 `k8s` 文档中不必要的配置。[1891](https://github.com/apache/apisix/pull/1891)


## 1.4.1

### Bugfix
- 修复在配置了多个 SSL 证书的情况下，只有一个证书生效的问题。 [1818](https://github.com/apache/incubator-apisix/pull/1818)

## 1.4.0

### Core
- Admin API: 路由支持唯一 name 字段 [1655](https://github.com/apache/incubator-apisix/pull/1655)
- 优化 log 缓冲区大小和刷新时间 [1570](https://github.com/apache/incubator-apisix/pull/1570)

### New plugins
- :sunrise: **Apache Skywalking plugin** [1241](https://github.com/apache/incubator-apisix/pull/1241)
- :sunrise: **Keycloak Identity Server Plugin** [1701](https://github.com/apache/incubator-apisix/pull/1701)
- :sunrise: **Echo Plugin** [1632](https://github.com/apache/incubator-apisix/pull/1632)
- :sunrise: **Consume Restriction Plugin** [1437](https://github.com/apache/incubator-apisix/pull/1437)

### Improvements
- Batch Request : 对每个请求拷贝头 [1697](https://github.com/apache/incubator-apisix/pull/1697)
- SSL 私钥加密 [1678](https://github.com/apache/incubator-apisix/pull/1678)
- 众多插件文档改善

## 1.3.0

1.3 版本主要带来安全更新。

## Security
- 拒绝无效的 header [#1462](https://github.com/apache/incubator-apisix/pull/1462) 并对 uri 进行安全编码 [#1461](https://github.com/apache/incubator-apisix/pull/1461)
- 默认只允许本地环回地址 127.0.0.1 访问 admin API 和 dashboard. [#1458](https://github.com/apache/incubator-apisix/pull/1458)

### Plugin
- :sunrise: **新增 batch request 插件**. [#1388](https://github.com/apache/incubator-apisix/pull/1388)
- 实现完成 `sys logger` 插件. [#1414](https://github.com/apache/incubator-apisix/pull/1414)


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
