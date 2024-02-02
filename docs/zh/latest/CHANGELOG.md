---
title: 版本发布
---

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

## Table of Contents

- [3.8.0](#380)
- [3.7.0](#370)
- [3.6.0](#360)
- [3.5.0](#350)
- [3.4.0](#340)
- [3.3.0](#330)
- [3.2.1](#321)
- [3.2.0](#320)
- [3.1.0](#310)
- [3.0.0](#300)
- [3.0.0-beta](#300-beta)
- [2.15.3](#2153)
- [2.15.2](#2152)
- [2.15.1](#2151)
- [2.15.0](#2150)
- [2.14.1](#2141)
- [2.14.0](#2140)
- [2.13.3](#2133)
- [2.13.2](#2132)
- [2.13.1](#2131)
- [2.13.0](#2130)
- [2.12.1](#2121)
- [2.12.0](#2120)
- [2.11.0](#2110)
- [2.10.5](#2105)
- [2.10.4](#2104)
- [2.10.3](#2103)
- [2.10.2](#2102)
- [2.10.1](#2101)
- [2.10.0](#2100)
- [2.9.0](#290)
- [2.8.0](#280)
- [2.7.0](#270)
- [2.6.0](#260)
- [2.5.0](#250)
- [2.4.0](#240)
- [2.3.0](#230)
- [2.2.0](#220)
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

## 3.8.0

### Core

- :sunrise: 支持使用 lua-resty-events 模块以提高性能：
  - [#10550](https://github.com/apache/apisix/pull/10550)
  - [#10558](https://github.com/apache/apisix/pull/10558)
- :sunrise: 将 OpenSSL 1.1.1 升级到 OpenSSL 3：[#10724](https://github.com/apache/apisix/pull/10724)

### Plugins

- :sunrise: 添加 jwe-decryp 插件：[#10252](https://github.com/apache/apisix/pull/10252)
- :sunrise: response-rewrite 插件使用 filters.regex 选项时支持 brotli：[#10733](https://github.com/apache/apisix/pull/10733)
- :sunrise: 添加多重认证插件：[#10482](https://github.com/apache/apisix/pull/10482)
- :sunrise: 在 `openid-connect` 插件中添加 `required scopes` 配置属性：[#10493](https://github.com/apache/apisix/pull/10493)
- :sunrise: cors 插件支持 Timing-Allow-Origin 头：[#9365](https://github.com/apache/apisix/pull/9365)
- :sunrise: 添加 brotli 插件：[#10515](https://github.com/apache/apisix/pull/10515)
- :sunrise: body-transformer 插件增强：[#10496](https://github.com/apache/apisix/pull/10496)
- :sunrise: limit-count 插件设置 redis_cluster_nodes 的最小长度为 1：[#10612](https://github.com/apache/apisix/pull/10612)
- :sunrise: 允许通过环境变量配置 limit-count 插件：[#10607](https://github.com/apache/apisix/pull/10607)

### Bugfixes

- 修复：upstream nodes 为数组类型时，port 应为可选字段：[#10477](https://github.com/apache/apisix/pull/10477)
- 修复：fault-injection 插件中变量提取不正确：[#10485](https://github.com/apache/apisix/pull/10485)
- 修复：所有消费者应共享同一计数器 (limit-count)：[#10541](https://github.com/apache/apisix/pull/10541)
- 修复：在向 opa 插件发送路由时安全地删除上游：[#10552](https://github.com/apache/apisix/pull/10552)
- 修复：缺少 etcd init_dir 和无法列出资源：[#10569](https://github.com/apache/apisix/pull/10569)
- 修复：Forward-auth 请求体过大：[#10589](https://github.com/apache/apisix/pull/10589)
- 修复：永不退出的定时器导致的内存泄漏：[#10614](https://github.com/apache/apisix/pull/10614)
- 修复：如果在 proxy-rewrite 插件中解析的值为 nil，则不调用 add_header：[#10619](https://github.com/apache/apisix/pull/10619)
- 修复：频繁遍历 etcd 所有的键，导致 cpu 使用率高：[#10671](https://github.com/apache/apisix/pull/10671)
- 修复：对于 prometheus 的 upstream_status 指标，mostly_healthy 是健康的：[#10639](https://github.com/apache/apisix/pull/10639)
- 修复：在 zipkin 中避免在日志阶段获取 nil 值：[#10666](https://github.com/apache/apisix/pull/10666)
- 修复：启用 openid-connect 插件而没有 redirect_uri 导致 500 错误：[#7690](https://github.com/apache/apisix/pull/7690)
- 修复：为没有 end_session_endpoint 的 ODIC 添加 redirect_after_logout_uri：[#10653](https://github.com/apache/apisix/pull/10653)
- 修复：当 content-encoding 为 gzip 时，response-rewrite 的 filters.regex 不适用：[#10637](https://github.com/apache/apisix/pull/10637)
- 修复：prometheus 指标的泄漏：[#10655](https://github.com/apache/apisix/pull/10655)
- 修复：Authz-keycloak 添加返回详细错误：[#10691](https://github.com/apache/apisix/pull/10691)
- 修复：服务发现未正确更新上游节点：[#10722](https://github.com/apache/apisix/pull/10722)
- 修复：apisix 重启失败：[#10696](https://github.com/apache/apisix/pull/10696)

## 3.7.0

### Change

- :warning: 创建核心资源时不允许传入 `create_time` 和 `update_time`：[#10232](https://github.com/apache/apisix/pull/10232)
- :warning: 从 SSL schema 中移除自包含的信息字段 `exptime`、`validity_start` 和 `validity_end`：[10323](https://github.com/apache/apisix/pull/10323)
- :warning: 在 opentelemetry 插件的属性中，将 `route` 替换为 `apisix.route_name`，将 `service` 替换为 `apisix.service_name`，以遵循 span 名称和属性的标准：[#10393](https://github.com/apache/apisix/pull/10393)

### Core

- :sunrise: 添加令牌以支持 Consul 的访问控制：[#10278](https://github.com/apache/apisix/pull/10278)
- :sunrise: 支持在 stream_route 中配置 `service_id` 引用 service 资源：[#10298](https://github.com/apache/apisix/pull/10298)
- :sunrise: 使用 `apisix-runtime` 作为 apisix 运行时：
  - [#10415](https://github.com/apache/apisix/pull/10415)
  - [#10427](https://github.com/apache/apisix/pull/10427)

### Plugins

- :sunrise: 为 authz-keycloak 添加测试，使用 apisix secrets：[#10353](https://github.com/apache/apisix/pull/10353)
- :sunrise: 向 openid-connect 插件添加授权参数：[#10058](https://github.com/apache/apisix/pull/10058)
- :sunrise: 支持在 zipkin 插件中设置变量：[#10361](https://github.com/apache/apisix/pull/10361)
- :sunrise: 支持 Nacos ak/sk 认证：[#10445](https://github.com/apache/apisix/pull/10445)

### Bugfixes

- 修复：获取健康检查目标状态失败时使用警告日志：
  - [#10156](https://github.com/apache/apisix/pull/10156)
- 修复：更新上游时应保留健康检查的状态：
  - [#10312](https://github.com/apache/apisix/pull/10312)
  - [#10307](https://github.com/apache/apisix/pull/10307)
- 修复：在插件配置模式中添加 name 字段以保持一致性：[#10315](https://github.com/apache/apisix/pull/10315)
- 修复：优化 upstream_schema 中的 tls 定义和错误的变量：[#10269](https://github.com/apache/apisix/pull/10269)
- 修复（consul）：无法正常退出：[#10342](https://github.com/apache/apisix/pull/10342)
- 修复：请求头 `Content-Type: application/x-www-form-urlencoded;charset=utf-8` 会导致 var 条件 `post_arg_xxx` 匹配失败：[#10372](https://github.com/apache/apisix/pull/10372)
- 修复：在 Mac 上安装失败：[#10403](https://github.com/apache/apisix/pull/10403)
- 修复（log-rotate）：日志压缩超时导致数据丢失：[#8620](https://github.com/apache/apisix/pull/8620)
- 修复（kafka-logger）：从 required_acks 枚举值中移除 0：[#10469](https://github.com/apache/apisix/pull/10469)

## 3.6.0

### Change

- :warning: 移除 `etcd.use_grpc`，不再支持使用 gRPC 协议与 etcd 进行通信：[#10015](https://github.com/apache/apisix/pull/10015)
- :warning: 移除 conf server，数据平面不再支持与控制平面进行通信，需要从 `config_provider: control_plane` 调整为 `config_provider: etcd`：[#10012](https://github.com/apache/apisix/pull/10012)
- :warning: 严格验证核心资源的输入：[#10233](https://github.com/apache/apisix/pull/10233)

### Core

- :sunrise: 支持配置访问日志的缓冲区大小：[#10225](https://github.com/apache/apisix/pull/10225)
- :sunrise: 支持在 DNS 发现服务中允许配置 `resolv_conf` 来使用本地 DNS 解析器：[#9770](https://github.com/apache/apisix/pull/9770)
- :sunrise: 安装不再依赖 Rust：[#10121](https://github.com/apache/apisix/pull/10121)
- :sunrise: 在 xRPC 中添加 Dubbo 协议支持：[#9660](https://github.com/apache/apisix/pull/9660)

### Plugins

- :sunrise: 在 `traffic-split` 插件中支持 HTTPS：[#9115](https://github.com/apache/apisix/pull/9115)
- :sunrise: 在 `ext-plugin` 插件中支持重写请求体：[#9990](https://github.com/apache/apisix/pull/9990)
- :sunrise: 在 `opentelemetry` 插件中支持设置 NGINX 变量：[#8871](https://github.com/apache/apisix/pull/8871)
- :sunrise: 在 `chaitin-waf` 插件中支持 UNIX sock 主机模式：[#10161](https://github.com/apache/apisix/pull/10161)

### Bugfixes

- 修复 GraphQL POST 请求路由匹配异常：[#10198](https://github.com/apache/apisix/pull/10198)
- 修复 `apisix.yaml` 中多行字符串数组的错误：[#10193](https://github.com/apache/apisix/pull/10193)
- 修复在 proxy-cache 插件中缺少 cache_zone 时提供错误而不是 nil panic：[#10138](https://github.com/apache/apisix/pull/10138)

## 3.5.0

### Change

- :warning: request-id 插件移除雪花算法：[#9715](https://github.com/apache/apisix/pull/9715)
- :warning: 不再兼容 OpenResty 1.19 版本，需要将其升级到 1.21+ 版本：[#9913](https://github.com/apache/apisix/pull/9913)
- :warning: 删除配置项 `apisix.stream_proxy.only`，L4/L7 代理需要通过配置项 `apesix.proxy_mode` 来启用：[#9607](https://github.com/apache/apisix/pull/9607)
- :warning: admin-api 的 `/apisix/admin/plugins?all=true` 接口标记为弃用：[#9580](https://github.com/apache/apisix/pull/9580)
- :warning: ua-restriction 插件不允许同时启用黑名单和白名单：[#9841](https://github.com/apache/apisix/pull/9841)

### Core

- :sunrise: 支持根据 host 级别动态设置 TLS 协议版本：[#9903](https://github.com/apache/apisix/pull/9903)
- :sunrise: 支持强制删除资源：[#9810](https://github.com/apache/apisix/pull/9810)
- :sunrise: 支持从 yaml 中提取环境变量：[#9855](https://github.com/apache/apisix/pull/9855)
- :sunrise: admin-api 新增 schema validate API 校验资源配置：[#10065](https://github.com/apache/apisix/pull/10065)

### Plugins

- :sunrise: 新增 chaitin-waf 插件：[#9838](https://github.com/apache/apisix/pull/9838)
- :sunrise: file-logger 支持设置 var 变量：[#9712](https://github.com/apache/apisix/pull/9712)
- :sunrise: mock 插件支持添加响应头：[#9720](https://github.com/apache/apisix/pull/9720)
- :sunrise: proxy-rewrite 插件支持正则匹配 URL 编码：[#9813](https://github.com/apache/apisix/pull/9813)
- :sunrise: google-cloud-logging 插件支持 client_email 配置：[#9813](https://github.com/apache/apisix/pull/9813)
- :sunrise: opa 插件支持向上游发送 OPA server 返回的头：[#9710](https://github.com/apache/apisix/pull/9710)
- :sunrise: openid-connect 插件支持配置代理服务器：[#9948](https://github.com/apache/apisix/pull/9948)

### Bugfixes

- 修复 log-rotate 插件使用自定义名称时，max_kept 配置不起作用：[#9749](https://github.com/apache/apisix/pull/9749)
- 修复 limit_conn 在 stream 模式下非法使用 http 变量：[#9816](https://github.com/apache/apisix/pull/9816)
- 修复 loki-logger 插件在获取 log_labels 时会索引空值：[#9850](https://github.com/apache/apisix/pull/9850)
- 修复使用 limit-count 插件时，当请求被拒绝后，X-RateLimit-Reset 不应设置为 0：[#9978](https://github.com/apache/apisix/pull/9978)
- 修复 nacos 插件在运行时索引一个空值：[#9960](https://github.com/apache/apisix/pull/9960)
- 修复 etcd 在同步数据时，如果密钥有特殊字符，则同步异常：[#9967](https://github.com/apache/apisix/pull/9967)
- 修复 tencent-cloud-cls 插件 DNS 解析失败：[#9843](https://github.com/apache/apisix/pull/9843)
- 修复执行 reload 或 quit 命令时 worker 未退出：[#9909](https://github.com/apache/apisix/pull/9909)
- 修复在 traffic-split 插件中 upstream_id 有效性验证：[#10008](https://github.com/apache/apisix/pull/10008)

## 3.4.0

### Core

- :sunrise: 支持路由级别的 MTLS [#9322](https://github.com/apache/apisix/pull/9322)
- :sunrise: 支持全局规则的 id schema [#9517](https://github.com/apache/apisix/pull/9517)
- :sunrise: 支持使用单个长连接来监视 etcd 的所有资源 [#9456](https://github.com/apache/apisix/pull/9456)
- :sunrise: 支持 ssl 标签的最大长度为 256 [#9301](https://github.com/apache/apisix/pull/9301)

### Plugins

- :sunrise: 支持 proxy_rewrite 插件的多个正则表达式匹配 [#9194](https://github.com/apache/apisix/pull/9194)
- :sunrise: 添加 loki-logger 插件 [#9399](https://github.com/apache/apisix/pull/9399)
- :sunrise: 允许用户为 prometheus 插件配置 DEFAULT_BUCKETS [#9673](https://github.com/apache/apisix/pull/9673)

### Bugfixes

- 修复 (body-transformer)：xml2lua 将空表替换为空字符串 [#9669](https://github.com/apache/apisix/pull/9669)
- 修复：opentelemetry 和 grpc-transcode 插件无法同时启用 [#9606](https://github.com/apache/apisix/pull/9606)
- 修复 (skywalking-logger, error-log-logger)：支持在 skywalking service_instance_name 中使用 $hostname [#9401](https://github.com/apache/apisix/pull/9401)
- 修复 (admin)：修复 secrets 不支持通过 PATCH 更新属性 [#9510](https://github.com/apache/apisix/pull/9510)
- 修复 (http-logger)：默认请求路径应为'/' [#9472](https://github.com/apache/apisix/pull/9472)
- 修复：syslog 插件不起作用 [#9425](https://github.com/apache/apisix/pull/9425)
- 修复：splunk-hec-logging 的日志格式错误 [#9478](https://github.com/apache/apisix/pull/9478)
- 修复：etcd 复用 cli 并启用 keepalive [#9420](https://github.com/apache/apisix/pull/9420)
- 修复：upstream key 添加 mqtt_client_id 支持 [#9450](https://github.com/apache/apisix/pull/9450)
- 修复：body-transformer 插件总是返回原始 body [#9446](https://github.com/apache/apisix/pull/9446)
- 修复：当 consumer 使用 wolf-rbac 插件时，consumer 中的其他插件无效 [#9298](https://github.com/apache/apisix/pull/9298)
- 修复：当 host 是域名时，总是解析域名 [#9332](https://github.com/apache/apisix/pull/9332)
- 修复：response-rewrite 插件不能只添加一个字符 [#9372](https://github.com/apache/apisix/pull/9372)
- 修复：consul 支持只获取 health endpoint [#9204](https://github.com/apache/apisix/pull/9204)

## 3.3.0

### Change

- 默认路由从 `radixtree_uri` 修改为 `radixtree_host_uri`: [#9047](https://github.com/apache/apisix/pull/9047)
- CORS 插件将会在 `allow_origin` 不为 `*` 时默认添加 `Vary: Origin` 响应头：[#9010](https://github.com/apache/apisix/pull/9010)

### Core

- :sunrise: 支持将路由证书存储在 secrets manager 中：[#9247](https://github.com/apache/apisix/pull/9247)
- :sunrise: 支持通过配置绕过 Admin API 身份验证：[#9147](https://github.com/apache/apisix/pull/9147)

### Plugins

- :sunrise: fault-injection 插件支持请求头注入：[#9039](https://github.com/apache/apisix/pull/9039)
- :sunrise: 提供在其他插件中引用 proxy-rewrite 插件中路由改写捕捉到的变量支持：[#9112](https://github.com/apache/apisix/pull/9112)
- :sunrise: limit-count 插件提供 `username` 与 `ssl` redis 认证方式：[#9185](https://github.com/apache/apisix/pull/9185)

### Bugfixes

- 修复 etcd 数据同步异常：[#8493](https://github.com/apache/apisix/pull/8493)
- 修复在 `core.request.add_header` 中的无效缓存：[#8824](https://github.com/apache/apisix/pull/8824)
- 修复由健康检查引起的高 CPU 和内存占用：[#9015](https://github.com/apache/apisix/pull/9015)
- 仅当 `allow_origins_by_regex` 不为 `nil` 时生效：[#9028](https://github.com/apache/apisix/pull/9028)
- 在删除 upstream 时，检查 `traffic-split` 插件中的引用：[#9044](https://github.com/apache/apisix/pull/9044)
- 修复启动时无法连接到 etcd 的问题：[#9077](https://github.com/apache/apisix/pull/9077)
- 修复域节点的健康检查泄漏问题：[#9090](https://github.com/apache/apisix/pull/9090)
- 禁止非 `127.0.0.0/24` 的用户在没有 admin_key 的情况下访问 Admin API: [#9146](https://github.com/apache/apisix/pull/9146)
- 确保 hold_body_chunk 函数对每个插件设置独立缓冲区，避免数据污染：[#9266](https://github.com/apache/apisix/pull/9266)
- 确保 batch-requests 插件能够在尾部响应头存在时能够正确读取：[#9289](https://github.com/apache/apisix/pull/9289)
- 确保 `proxy-rewrite` 改写 `ngx.var.uri`: [#9309](https://github.com/apache/apisix/pull/9309)

## 3.2.1

**这是一个 LTS 维护版本，您可以在 `release/3.2` 分支中看到 CHANGELOG。**

## 3.2.0

### Change

- 废弃了 jwt-auth 内单独的 Vault 配置。用户能用密钥来实现同样的功能：[#8660](https://github.com/apache/apisix/pull/8660)

### Core

- :sunrise: 支持通过环境变量来配置密钥的 Vault token：[#8866](https://github.com/apache/apisix/pull/8866)
- :sunrise: 支持四层上的服务发现：
    - [#8583](https://github.com/apache/apisix/pull/8583)
    - [#8593](https://github.com/apache/apisix/pull/8593)
    - [#8584](https://github.com/apache/apisix/pull/8584)
    - [#8640](https://github.com/apache/apisix/pull/8640)
    - [#8633](https://github.com/apache/apisix/pull/8633)
    - [#8696](https://github.com/apache/apisix/pull/8696)
    - [#8826](https://github.com/apache/apisix/pull/8826)

### Plugin

- :sunrise: 新增 RESTful 请求转 graphQL 的插件：[#8959](https://github.com/apache/apisix/pull/8959)
- :sunrise: 支持在每个日志插件上设置日志格式：
    - [#8806](https://github.com/apache/apisix/pull/8806)
    - [#8643](https://github.com/apache/apisix/pull/8643)
- :sunrise: 新增请求体/响应体转换插件：[#8766](https://github.com/apache/apisix/pull/8766)
- :sunrise: 支持发送错误日志到 Kafka：[#8693](https://github.com/apache/apisix/pull/8693)
- :sunrise: limit-count 插件支持 X-RateLimit-Reset：[#8578](https://github.com/apache/apisix/pull/8578)
- :sunrise: limit-count 插件支持设置 TLS 来访问 Redis 集群：[#8558](https://github.com/apache/apisix/pull/8558)
- :sunrise: consumer-restriction 插件支持通过 consumer_group_id 来做权限控制：[#8567](https://github.com/apache/apisix/pull/8567)

### Bugfix

- 修复 Host 和 SNI 不匹配时，mTLS 失效的问题：[#8967](https://github.com/apache/apisix/pull/8967)
- 如果 URI 参数部分不来自于用户配置，proxy-rewrite 插件应当对其转义：[#8888](https://github.com/apache/apisix/pull/8888)
- Admin API PATCH 操作成功后应返回 200 状态码：[#8855](https://github.com/apache/apisix/pull/8855)
- 修复特定条件下，etcd 同步失败之后的 reload 不生效：[#8736](https://github.com/apache/apisix/pull/8736)
- 修复 Consul 服务发现得到的节点不全的问题：[#8651](https://github.com/apache/apisix/pull/8651)
- 修复 grpc-transcode 插件对 Map 数据的转换问题：[#8731](https://github.com/apache/apisix/pull/8731)
- 外部插件应当可以设置 content-type 响应头：[#8588](https://github.com/apache/apisix/pull/8588)
- 插件热加载时，如果 request-id 插件中初始化 snowflake 生成器出错，可能遗留多余的计时器：[#8556](https://github.com/apache/apisix/pull/8556)
- 插件热加载时，关闭 grpc-transcode 的 proto 同步器：[#8557](https://github.com/apache/apisix/pull/8557)

## 3.1.0

### Core

- :sunrise: 支持通过 gRPC 来同步 etcd 的配置：
    - [#8485](https://github.com/apache/apisix/pull/8485)
    - [#8450](https://github.com/apache/apisix/pull/8450)
    - [#8411](https://github.com/apache/apisix/pull/8411)
- :sunrise: 支持在插件中配置加密字段：
    - [#8487](https://github.com/apache/apisix/pull/8487)
    - [#8403](https://github.com/apache/apisix/pull/8403)
- :sunrise: 支持使用 secret 资源将部分字段放到 Vault 或环境变量中：
    - [#8448](https://github.com/apache/apisix/pull/8448)
    - [#8421](https://github.com/apache/apisix/pull/8421)
    - [#8412](https://github.com/apache/apisix/pull/8412)
    - [#8394](https://github.com/apache/apisix/pull/8394)
    - [#8390](https://github.com/apache/apisix/pull/8390)
- :sunrise: 允许在 stream 子系统中以域名的形式配置上游：[#8500](https://github.com/apache/apisix/pull/8500)
- :sunrise: 支持 Consul 服务发现：[#8380](https://github.com/apache/apisix/pull/8380)

### Plugin

- :sunrise: 优化 prometheus 采集的资源占用：[#8434](https://github.com/apache/apisix/pull/8434)
- :sunrise: 增加便于调试的 inspect 插件： [#8400](https://github.com/apache/apisix/pull/8400)
- :sunrise: jwt-auth 插件支持对上游隐蔽认证的参数：[#8206](https://github.com/apache/apisix/pull/8206)
- :sunrise: proxy-rewrite 插件支持新增请求头的同时不覆盖现有同名请求头：[#8336](https://github.com/apache/apisix/pull/8336)
- :sunrise: grpc-transcode 插件支持将 grpc-status-details-bin 响应头设置到响应体中：[#7639](https://github.com/apache/apisix/pull/7639)
- :sunrise: proxy-mirror 插件支持设置前缀：[#8261](https://github.com/apache/apisix/pull/8261)

### Bugfix

- 修复某些情况下，配置在 service 对象下的插件无法及时生效的问题：[#8482](https://github.com/apache/apisix/pull/8482)
- 修复因连接池复用，http 和 grpc 共用同一个上游节点时偶发 502 的问题：[#8364](https://github.com/apache/apisix/pull/8364)
- file-logger 在写日志时，应避免缓冲区造成的日志截断：[#7884](https://github.com/apache/apisix/pull/7884)
- log-rotate 插件的 max_kept 参数应对压缩文件生效：[#8366](https://github.com/apache/apisix/pull/8366)
- 修复 openid-connect 插件中当 use_jwks 为 true 时没有设置 userinfo 的问题：[#8347](https://github.com/apache/apisix/pull/8347)
- 修复无法在 proxy-rewrite 插件中修改 x-forwarded-host 的问题：[#8200](https://github.com/apache/apisix/pull/8200)
- 修复某些情况下，禁用 v3 admin API 导致响应体丢失：[#8349](https://github.com/apache/apisix/pull/8349)
- zipkin 插件中，即使存在 reject 的 sampling decision，也要传递 trace ID：[#8099](https://github.com/apache/apisix/pull/8099)
- 修复插件配置中的 `_meta.filter` 无法使用上游响应后才赋值的变量和 APISIX 中自定义变量的问题：
    - [#8162](https://github.com/apache/apisix/pull/8162)
    - [#8256](https://github.com/apache/apisix/pull/8256)

## 3.0.0

### Change

- 默认关闭 `enable_cpu_affinity`，避免在容器部署场景中该配置影响 APSISIX 的行为：[#8074](https://github.com/apache/apisix/pull/8074)

### Core

- :sunrise: 新增 Consumer Group 实体，用于管理多个 Consumer：[#7980](https://github.com/apache/apisix/pull/7980)
- :sunrise: 支持配置 DNS 解析域名类型的顺序：[#7935](https://github.com/apache/apisix/pull/7935)
- :sunrise: 支持配置多个 `key_encrypt_salt` 进行轮转：[#7925](https://github.com/apache/apisix/pull/7925)

### Plugin

- :sunrise: 新增 ai 插件，根据场景动态优化 APISIX 的执行路径：
    - [#8102](https://github.com/apache/apisix/pull/8102)
    - [#8113](https://github.com/apache/apisix/pull/8113)
    - [#8120](https://github.com/apache/apisix/pull/8120)
    - [#8128](https://github.com/apache/apisix/pull/8128)
    - [#8130](https://github.com/apache/apisix/pull/8130)
    - [#8149](https://github.com/apache/apisix/pull/8149)
    - [#8157](https://github.com/apache/apisix/pull/8157)
- :sunrise: openid-connect 插件支持设置 `session_secret`，解决多个 worker 间 `session_secret` 不一致的问题：[#8068](https://github.com/apache/apisix/pull/8068)
- :sunrise: kafka-logger 插件支持设置 sasl 相关配置：[#8050](https://github.com/apache/apisix/pull/8050)
- :sunrise: proxy-mirror 插件支持设置域名作为 host：[#7861](https://github.com/apache/apisix/pull/7861)
- :sunrise: kafka-logger 插件新增 brokers 属性，支持不同 broker 设置相同 host：[#7999](https://github.com/apache/apisix/pull/7999)
- :sunrise: ext-plugin-post-resp 插件支持获取上游响应体：[#7947](https://github.com/apache/apisix/pull/7947)
- :sunrise: 新增 cas-auth 插件，支持 CAS 认证：[#7932](https://github.com/apache/apisix/pull/7932)

### Bugfix

- workflow 插件的条件表达式应该支持操作符：[#8121](https://github.com/apache/apisix/pull/8121)
- 修复禁用 prometheus 插件时 batch processor 加载问题：[#8079](https://github.com/apache/apisix/pull/8079)
- APISIX 启动时，如果存在旧的 conf server 的 sock 文件则删除：[#8022](https://github.com/apache/apisix/pull/8022)
- 没有编译 gRPC-client-nginx-module 模块时禁用 core.grpc：[#8007](https://github.com/apache/apisix/pull/8007)

## 3.0.0-beta

这里我们使用 `2.99.0` 作为源代码中的版本号，而不是代码名称
`3.0.0-beta`，有两个原因。

1. 避免在一些程序试图比较版本时出现意外的错误，因为 `3.0.0-beta` 包含 `3.0.0` 并且比它长。
2. 一些软件包系统可能不允许在版本号后面有一个后缀。

### Change

#### 移动 config_center、etcd 和 Admin API 的配置到 deployment 下面

我们调整了下静态配置文件里面的配置，所以你需要同步更新下 config.yaml 里面的配置了：

- `config_center` 功能改由 `deployment` 下面的 `config_provider` 实现： [#7901](https://github.com/apache/apisix/pull/7901)
- `etcd` 字段整体搬迁到 `deployment` 下面： [#7860](https://github.com/apache/apisix/pull/7860)
- 以下的 Admin API 配置移动到 `deployment` 下面的 `admin` 字段：[#7823](https://github.com/apache/apisix/pull/7823)
    - admin_key
    - enable_admin_cors
    - allow_admin
    - admin_listen
    - https_admin
    - admin_api_mtls
    - admin_api_version

具体可以参考最新的 config-default.yaml。

#### 移除多个已废弃的配置

借着 3.0 新版本的机会，我们把许多之前标记为 deprecated 的配置清理出去。

在静态配置中，我们移除了以下若干字段：

- 移除 `apisix.ssl` 中的 `enable_http2` 和 `listen_port`：[#7717](https://github.com/apache/apisix/pull/7717)
- 移除 `apisix.port_admin`： [#7716](https://github.com/apache/apisix/pull/7716)
- 移除 `etcd.health_check_retry`： [#7676](https://github.com/apache/apisix/pull/7676)
- 移除 `nginx_config.http.lua_shared_dicts`： [#7677](https://github.com/apache/apisix/pull/7677)
- 移除 `apisix.real_ip_header`: [#7696](https://github.com/apache/apisix/pull/7696)

在动态配置中，我们做了以下调整：

- 将插件配置的 `disable` 移到 `_meta` 下面：[#7707](https://github.com/apache/apisix/pull/7707)
- 从 Route 里面移除了 `service_protocol`：[#7701](https://github.com/apache/apisix/pull/7701)

此外还有具体插件级别上的改动：

- authz-keycloak 中移除了 `audience` 字段： [#7683](https://github.com/apache/apisix/pull/7683)
- mqtt-proxy 中移除了 `upstream` 字段：[#7694](https://github.com/apache/apisix/pull/7694)
- error-log-logger 中把 tcp 相关配置放到 `tcp` 字段下面：[#7700](https://github.com/apache/apisix/pull/7700)
- syslog 中移除了 `max_retry_times` 和 `retry_interval` 字段： [#7699](https://github.com/apache/apisix/pull/7699)
- proxy-rewrite 中移除了 `scheme` 字段： [#7695](https://github.com/apache/apisix/pull/7695)

#### 新的 Admin API 响应格式

我们在以下若干个 PR 中调整了 Admin API 的响应格式：

- [#7630](https://github.com/apache/apisix/pull/7630)
- [#7622](https://github.com/apache/apisix/pull/7622)

新的响应格式展示如下：

返回单个配置：

```json
{
  "modifiedIndex": 2685183,
  "value": {
    "id": "1",
    ...
  },
  "key": "/apisix/routes/1",
  "createdIndex": 2684956
}
```

返回多个配置：

```json
{
  "list": [
    {
      "modifiedIndex": 2685183,
      "value": {
        "id": "1",
        ...
      },
      "key": "/apisix/routes/1",
      "createdIndex": 2684956
    },
    {
      "modifiedIndex": 2685163,
      "value": {
        "id": "2",
        ...
      },
      "key": "/apisix/routes/2",
      "createdIndex": 2685163
    }
  ],
  "total": 2
}
```

#### 其他

- Admin API 的端口改为 9180：[#7806](https://github.com/apache/apisix/pull/7806)
- 我们只支持 OpenResty 1.19.3.2 及以上的版本：[#7625](https://github.com/apache/apisix/pull/7625)
- 调整了 Plugin Config 对象的优先级，同名插件配置的优先级由 Consumer > Plugin Config > Route > Service 变成 Consumer > Route > Plugin Config > Service： [#7614](https://github.com/apache/apisix/pull/7614)

### Core

- 集成 grpc-client-nginx-module 到 APISIX： [#7917](https://github.com/apache/apisix/pull/7917)
- k8s 服务发现支持配置多个集群：[#7895](https://github.com/apache/apisix/pull/7895)

### Plugin

- 支持在 opentelemetry 插件里注入指定前缀的 header：[#7822](https://github.com/apache/apisix/pull/7822)
- 新增 openfunction 插件：[#7634](https://github.com/apache/apisix/pull/7634)
- 新增 elasticsearch-logger 插件：[#7643](https://github.com/apache/apisix/pull/7643)
- response-rewrite 插件支持增加响应体：[#7794](https://github.com/apache/apisix/pull/7794)
- log-rorate 支持指定最大大小来切割日志：[#7749](https://github.com/apache/apisix/pull/7749)
- 新增 workflow 插件：
    - [#7760](https://github.com/apache/apisix/pull/7760)
    - [#7771](https://github.com/apache/apisix/pull/7771)
- 新增 Tencent Cloud Log Service 插件：[#7593](https://github.com/apache/apisix/pull/7593)
- jwt-auth 支持 ES256 算法： [#7627](https://github.com/apache/apisix/pull/7627)
- ldap-auth 内部实现，由 lualdap 换成 lua-resty-ldap：[#7590](https://github.com/apache/apisix/pull/7590)
- prometheus 插件内的 http request metrics 支持通过变量来设置额外的 labels：[#7549](https://github.com/apache/apisix/pull/7549)
- clickhouse-logger 插件支持指定多个 clickhouse endpoints: [#7517](https://github.com/apache/apisix/pull/7517)

### Bugfix

- gRPC 代理设置 :authority 请求头为配置的上游 Host： [#7939](https://github.com/apache/apisix/pull/7939)
- response-rewrite 写入空 body 时有可能导致 AIPSIX 无法响应该请求：[#7836](https://github.com/apache/apisix/pull/7836)
- 修复同时使用 Plugin Config 和 Consumer，有一定概率发生插件配置没有更新的问题：[#7965](https://github.com/apache/apisix/pull/7965)
- 日志切割时，只 reopen 一次日志文件：[#7869](https://github.com/apache/apisix/pull/7869)
- 默认不应开启被动健康检查： [#7850](https://github.com/apache/apisix/pull/7850)
- zipkin 插件即使不进行 sample，也要向上游传递 trace IDs： [#7833](https://github.com/apache/apisix/pull/7833)
- 将 opentelemetry 的 span kind 更正为 server: [#7830](https://github.com/apache/apisix/pull/7830)
- limit-count 插件中，同样配置的不同路由不应该共享同一个计数器：[#7750](https://github.com/apache/apisix/pull/7750)
- 修复偶发的移除 clean_handler 时抛异常的问题： [#7648](https://github.com/apache/apisix/pull/7648)
- 允许配置上游节点时直接使用 IPv6 字面量： [#7594](https://github.com/apache/apisix/pull/7594)
- wolf-rbac 插件调整对错误的响应方式：
    - [#7561](https://github.com/apache/apisix/pull/7561)
    - [#7497](https://github.com/apache/apisix/pull/7497)
- 当代理到上游之前发生 500 错误时，代理到上游之后运行的插件不应被跳过 [#7703](https://github.com/apache/apisix/pull/7703)
- 当 consumer 上绑定了多个插件且该插件定义了 rewrite 方法时，避免抛出异常 [#7531](https://github.com/apache/apisix/pull/7531)
- 升级 lua-resty-etcd 到 1.8.3。该版本修复了若干问题。 [#7565](https://github.com/apache/apisix/pull/7565)

## 2.15.3

**这是一个 LTS 维护版本，您可以在 `release/2.15` 分支中看到 CHANGELOG。**

## 2.15.2

**这是一个 LTS 维护版本，您可以在 `release/2.15` 分支中看到 CHANGELOG。**

## 2.15.1

**这是一个 LTS 维护版本，您可以在 `release/2.15` 分支中看到 CHANGELOG。**

## 2.15.0

### Change

- grpc 状态码 OUT_OF_RANGE 如今会在 grpc-transcode 插件中作为 http 状态码 400: [#7419](https://github.com/apache/apisix/pull/7419)
- 重命名 `etcd.health_check_retry` 配置项为 `startup_retry`。 [#7304](https://github.com/apache/apisix/pull/7304)
- 移除 `upstream.enable_websocket`。该配置已于 2020 年标记成已过时。 [#7222](https://github.com/apache/apisix/pull/7222)

### Core

- 支持动态启用插件 [#7453](https://github.com/apache/apisix/pull/7453)
- 支持动态指定插件执行顺序 [#7273](https://github.com/apache/apisix/pull/7273)
- 支持 Upstream 对象从 SSL 对象中引用证书 [#7221](https://github.com/apache/apisix/pull/7221)
- 允许在插件中使用自定义错误 [#7128](https://github.com/apache/apisix/pull/7128)
- xRPC Redis 代理增加 metrics: [#7183](https://github.com/apache/apisix/pull/7183)
- 引入 deployment role 概念来简化 APISIX 的部署：
    - [#7405](https://github.com/apache/apisix/pull/7405)
    - [#7417](https://github.com/apache/apisix/pull/7417)
    - [#7392](https://github.com/apache/apisix/pull/7392)
    - [#7365](https://github.com/apache/apisix/pull/7365)
    - [#7249](https://github.com/apache/apisix/pull/7249)

### Plugin

- prometheus 指标中提供 ngx.shared.dict 统计信息 [#7412](https://github.com/apache/apisix/pull/7412)
- 允许在 proxy-rewrite 插件中使用客户端发过来的原始 URL [#7401](https://github.com/apache/apisix/pull/7401)
- openid-connect 插件支持 PKCE： [#7370](https://github.com/apache/apisix/pull/7370)
- sls-logger 插件支持自定义日志格式 [#7328](https://github.com/apache/apisix/pull/7328)
- kafka-logger 插件支持更多的 Kafka 客户端配置 [#7266](https://github.com/apache/apisix/pull/7266)
- openid-connect 插件支持暴露 refresh token [#7220](https://github.com/apache/apisix/pull/7220)
- 移植 prometheus 插件到 stream 子系统 [#7174](https://github.com/apache/apisix/pull/7174)

### Bugfix

- Kubernetes 服务发现在重试时应当清除上一次尝试时遗留的状态 [#7506](https://github.com/apache/apisix/pull/7506)
- redirect 插件禁止同时启用冲突的 http_to_https 和 append_query_string 配置 [#7433](https://github.com/apache/apisix/pull/7433)
- 默认配置下，http-logger 不再发送空 Authorization 头 [#7444](https://github.com/apache/apisix/pull/7444)
- 修复 limit-count 插件不能同时配置 group 和 disable 的问题 [#7384](https://github.com/apache/apisix/pull/7384)
- 让 request-id 插件优先执行，这样 tracing 插件可以用到 request id [#7281](https://github.com/apache/apisix/pull/7281)
- 更正 grpc-transcode 插件中对 repeated Message 的处理。 [#7231](https://github.com/apache/apisix/pull/7231)
- 允许 proxy-cache 插件 cache key 出现缺少的值。 [#7168](https://github.com/apache/apisix/pull/7168)
- 减少 chash 负载均衡节点权重过大时额外的内存消耗。 [#7103](https://github.com/apache/apisix/pull/7103)
- proxy-cache 插件 method 不匹配时不应该返回缓存结果。 [#7111](https://github.com/apache/apisix/pull/7111)
- 上游 keepalive 应考虑 TLS 参数：
    - [#7054](https://github.com/apache/apisix/pull/7054)
    - [#7466](https://github.com/apache/apisix/pull/7466)
- 重定向插件在将 HTTP 重定向到 HTTPS 时设置了正确的端口。
    - [#7065](https://github.com/apache/apisix/pull/7065)

## 2.14.1

### Bugfix

- `real_ip_from` 中配置 "unix: " 不应该导致 batch-requests 插件无法使用 [#7106](https://github.com/apache/apisix/pull/7106)

## 2.14.0

### Change

- 为了适应 OpenTelemetry 规范的变化，OTLP/HTTP 的默认端口改为 4318: [#7007](https://github.com/apache/apisix/pull/7007)

### Core

- 引入一个实验性功能，允许通过 APISIX 订阅 Kafka 消息。这个功能是基于 websocket 上面运行的 pubsub 框架。
    - [#7028](https://github.com/apache/apisix/pull/7028)
    - [#7032](https://github.com/apache/apisix/pull/7032)
- 引入一个名为 xRPC 的实验性框架来管理非 HTTP 的 L7 流量。
    - [#6885](https://github.com/apache/apisix/pull/6885)
    - [#6901](https://github.com/apache/apisix/pull/6901)
    - [#6919](https://github.com/apache/apisix/pull/6919)
    - [#6960](https://github.com/apache/apisix/pull/6960)
    - [#6965](https://github.com/apache/apisix/pull/6965)
    - [#7040](https://github.com/apache/apisix/pull/7040)
- 现在我们支持在代理 Redis traffic 过程中根据命令和键添加延迟，它建立在 xRPC 之上。
    - [#6999](https://github.com/apache/apisix/pull/6999)
- 引入实验性支持，通过 xDS 配置 APISIX。
    - [#6614](https://github.com/apache/apisix/pull/6614)
    - [#6759](https://github.com/apache/apisix/pull/6759)
- 增加 `normalize_uri_like_servlet` 配置选项，像 servlet 一样规范化 URI。[#6984](https://github.com/apache/apisix/pull/6984)
- 通过 apisix-seed 实现 Zookeeper 服务发现：[#6751](https://github.com/apache/apisix/pull/6751)

### Plugin

- real-ip 插件支持像 `real_ip_recursive` 那样的递归 IP 搜索。[#6988](https://github.com/apache/apisix/pull/6988)
- api-breaker 插件允许配置响应。[#6949](https://github.com/apache/apisix/pull/6949)
- response-rewrite 插件支持正文过滤器。[#6750](https://github.com/apache/apisix/pull/6750)
- request-id 插件增加了 nanoid 算法来生成 ID：[#6779](https://github.com/apache/apisix/pull/6779)
- file-logger 插件可以缓存和重开 file handler。[#6721](https://github.com/apache/apisix/pull/6721)
- 增加 casdoor 插件。[#6382](https://github.com/apache/apisix/pull/6382)
- authz-keycloak 插件支持 password grant：[#6586](https://github.com/apache/apisix/pull/6586)

### Bugfix

- 上游 keepalive 应考虑 TLS 参数：[#7054](https://github.com/apache/apisix/pull/7054)
- 不要将内部错误信息暴露给客户端。
    - [#6982](https://github.com/apache/apisix/pull/6982)
    - [#6859](https://github.com/apache/apisix/pull/6859)
    - [#6854](https://github.com/apache/apisix/pull/6854)
    - [#6853](https://github.com/apache/apisix/pull/6853)
    - [#6846](https://github.com/apache/apisix/pull/6846)
- DNS 支持端口为 0 的 SRV 记录：[#6739](https://github.com/apache/apisix/pull/6739)
- 修复客户端 mTLS 在 TLS 会话重用中有时不生效的问题：[#6906](https://github.com/apache/apisix/pull/6906)
- grpc-web 插件不会在响应中覆盖 Access-Control-Allow-Origin 头。[#6842](https://github.com/apache/apisix/pull/6842)
- syslog 插件的默认超时已被纠正。[#6807](https://github.com/apache/apisix/pull/6807)
- 修复 authz-keycloak 插件的 `access_denied_redirect_uri` 的设置有时不生效的问题。[#6794](https://github.com/apache/apisix/pull/6794)
- 正确处理 `USR2` 信号。[#6758](https://github.com/apache/apisix/pull/6758)
- 重定向插件在将 HTTP 重定向到 HTTPS 时设置了正确的端口。
    - [#7065](https://github.com/apache/apisix/pull/7065)
    - [#6686](https://github.com/apache/apisix/pull/6686)
- Admin API 拒绝未知的 stream 插件。[#6813](https://github.com/apache/apisix/pull/6813)

## 2.13.3

**这是一个 LTS 维护版本，您可以在 `release/2.13` 分支中看到 CHANGELOG。**

## 2.13.2

**这是一个 LTS 维护版本，您可以在 `release/2.13` 分支中看到 CHANGELOG。**

## 2.13.1

**这是一个 LTS 维护版本，您可以在 `release/2.13` 分支中看到 CHANGELOG。**

## 2.13.0

### Change

- 更正 syslog 插件的配置 [#6551](https://github.com/apache/apisix/pull/6551)
- server-info 插件使用新方法来上报 DP 面信息 [#6202](https://github.com/apache/apisix/pull/6202)
- Admin API 返回的空 nodes 应当被编码为数组 [#6384](https://github.com/apache/apisix/pull/6384)
- 更正 prometheus 统计指标 apisix_nginx_http_current_connections{state="total"} [#6327](https://github.com/apache/apisix/pull/6327)
- 不再默认暴露 public API 并移除 plugin interceptor [#6196](https://github.com/apache/apisix/pull/6196)

### Core

- :sunrise: 新增 delayed_body_filter 阶段 [#6605](https://github.com/apache/apisix/pull/6605)
- :sunrise: standalone 模式的配置支持环境变量 [#6505](https://github.com/apache/apisix/pull/6505)
- :sunrise: consumer 新增的插件都能被执行 [#6502](https://github.com/apache/apisix/pull/6502)
- :sunrise: 添加配置项来控制是否在 x-upsream-apisix-status 中记录所有状态码 [#6392](https://github.com/apache/apisix/pull/6392)
- :sunrise: 新增 kubernetes 服务发现 [#4880](https://github.com/apache/apisix/pull/4880)
- :sunrise: graphql 路由支持 JSON 类型和 GET 方法 [#6343](https://github.com/apache/apisix/pull/6343)

### Plugin

- :sunrise: jwt-auth 支持自定义参数名 [#6561](https://github.com/apache/apisix/pull/6561)
- :sunrise: cors 参数支持通过 plugin metadata 配置 [#6546](https://github.com/apache/apisix/pull/6546)
- :sunrise: openid-connect 支持 post_logout_redirect_uri [#6455](https://github.com/apache/apisix/pull/6455)
- :sunrise: mocking 插件 [#5940](https://github.com/apache/apisix/pull/5940)
- :sunrise: error-log-logger 新增 clickhouse 支持 [#6256](https://github.com/apache/apisix/pull/6256)
- :sunrise: clickhouse 日志插件 [#6215](https://github.com/apache/apisix/pull/6215)
- :sunrise: grpc-transcode 支持处理 .pb 文件 [#6264](https://github.com/apache/apisix/pull/6264)
- :sunrise: loggly 日志插件 [#6113](https://github.com/apache/apisix/pull/6113)
- :sunrise: opentelemetry 日志插件 [#6119](https://github.com/apache/apisix/pull/6119)
- :sunrise: public api 插件 [#6145](https://github.com/apache/apisix/pull/6145)
- :sunrise: CSRF 插件 [#5727](https://github.com/apache/apisix/pull/5727)

### Bugfix

- 修复 skywalking,opentelemetry 没有追踪认证失败的问题 [#6617](https://github.com/apache/apisix/pull/6617)
- log-rotate 切割日志时按整点完成 [#6521](https://github.com/apache/apisix/pull/6521)
- deepcopy 没有复制 metatable [#6623](https://github.com/apache/apisix/pull/6623)
- request-validate 修复对 JSON 里面重复键的处理 [#6625](https://github.com/apache/apisix/pull/6625)
- prometheus 避免重复计算指标 [#6579](https://github.com/apache/apisix/pull/6579)
- 修复 proxy-rewrite 中，当 conf.headers 缺失时，conf.method 不生效的问题 [#6300](https://github.com/apache/apisix/pull/6300)
- 修复 traffic-split 首条规则失败时无法匹配的问题 [#6292](https://github.com/apache/apisix/pull/6292)
- etcd 超时不应触发 resync_delay [#6259](https://github.com/apache/apisix/pull/6259)
- 解决 proto 定义冲突 [#6199](https://github.com/apache/apisix/pull/6199)
- limit-count 配置不变，不应重置计数器 [#6151](https://github.com/apache/apisix/pull/6151)
- Admin API 的 plugin-metadata 和 global-rule 计数有误 [#6155](https://github.com/apache/apisix/pull/6155)
- 解决合并 route 和 service 时 labels 丢失问题 [#6177](https://github.com/apache/apisix/pull/6177)

## 2.12.1

**这是一个 LTS 维护版本，您可以在 `release/2.12` 分支中看到 CHANGELOG。**

## 2.12.0

### Change

- 重命名 serverless 插件的 "balancer" phase 为 "before_proxy" [#5992](https://github.com/apache/apisix/pull/5992)
- 不再承诺支持 Tengine [#5961](https://github.com/apache/apisix/pull/5961)
- 当 L4 支持 和 Admin API 都启用时，自动开启 HTTP 支持 [#5867](https://github.com/apache/apisix/pull/5867)

### Core

- :sunrise: 支持 TLS over TCP upstream [#6030](https://github.com/apache/apisix/pull/6030)
- :sunrise: 支持自定义 APISIX variable [#5941](https://github.com/apache/apisix/pull/5941)
- :sunrise: 支持集成 Vault [#5745](https://github.com/apache/apisix/pull/5745)
- :sunrise: 支持 L4 的 access log [#5768](https://github.com/apache/apisix/pull/5768)
- :sunrise: 支持自定义 http_server_location_configuration_snippet 配置 [#5740](https://github.com/apache/apisix/pull/5740)
- :sunrise: 支持配置文件环境变量中设置默认值 [#5675](https://github.com/apache/apisix/pull/5675)
- :sunrise: 支持在 header_filter 阶段运行 Wasm 代码 [#5544](https://github.com/apache/apisix/pull/5544)

### Plugin

- :sunrise: 支持在 basic-auth 中隐藏 Authorization 请求头 [#6039](https://github.com/apache/apisix/pull/6039)
- :sunrise: 支持动态设置 proxy_request_buffering [#6075](https://github.com/apache/apisix/pull/6075)
- :sunrise: mqtt 支持通过 client id 负载均衡 [#6079](https://github.com/apache/apisix/pull/6079)
- :sunrise: 添加 forward-auth 插件 [#6037](https://github.com/apache/apisix/pull/6037)
- :sunrise: 支持 gRPC-Web 代理 [#5964](https://github.com/apache/apisix/pull/5964)
- :sunrise: limit-count 支持请求间共享计数器 [#5984](https://github.com/apache/apisix/pull/5984)
- :sunrise: limit-count 支持在路由间共享计数器 [#5881](https://github.com/apache/apisix/pull/5881)
- :sunrise: 新增 splunk hec logging 插件 [#5819](https://github.com/apache/apisix/pull/5819)
- :sunrise: 新增 OPA 插件 [#5734](https://github.com/apache/apisix/pull/5734)
- :sunrise: 新增 rocketmq logger 插件 [#5653](https://github.com/apache/apisix/pull/5653)
- :sunrise: mqtt 支持直接使用 route 上配置的 upstream [#5666](https://github.com/apache/apisix/pull/5666)
- :sunrise: ext-plugin 支持获取请求体 [#5600](https://github.com/apache/apisix/pull/5600)
- :sunrise: 新增 aws lambda 插件 [#5594](https://github.com/apache/apisix/pull/5594)
- :sunrise: http/kafka-logger 插件支持记录响应体 [#5550](https://github.com/apache/apisix/pull/5550)
- :sunrise: 新增 Apache OpenWhisk 插件 [#5518](https://github.com/apache/apisix/pull/5518)
- :sunrise: 支持 google cloud logging service [#5538](https://github.com/apache/apisix/pull/5538)

### Bugfix

- 同时启用 error-log-logger 和 prometheusis 时报告 labels inconsistent 的问题 [#6055](https://github.com/apache/apisix/pull/6055)
- 支持禁止 IPv6 IP 解析 [#6023](https://github.com/apache/apisix/pull/6023)
- 正确处理 MQTT 5 中的 properties [#5916](https://github.com/apache/apisix/pull/5916)
- sls-logger 上报的 timestamp 补上毫秒部分 [#5820](https://github.com/apache/apisix/pull/5820)
- MQTT 中的 client id 可以为空 [#5816](https://github.com/apache/apisix/pull/5816)
- ext-plugin 避免使用过期的 key [#5782](https://github.com/apache/apisix/pull/5782)
- 解决 log-rotate 中 reopen log 和压缩中的 race [#5715](https://github.com/apache/apisix/pull/5715)
- 释放 batch-processor 中过期对象 [#5700](https://github.com/apache/apisix/pull/5700)
- 解决被动健康检查时配置被污染的问题 [#5589](https://github.com/apache/apisix/pull/5589)

## 2.11.0

### Change

- wolf-rbac 插件变更默认端口，并在文档中增加 authType 参数 [#5477](https://github.com/apache/apisix/pull/5477)

### Core

- :sunrise: 支持基于 POST 表单的高级路由匹配 [#5409](https://github.com/apache/apisix/pull/5409)
- :sunrise: 初步的 WASM 支持 [#5288](https://github.com/apache/apisix/pull/5288)
- :sunrise: control API 暴露 service 配置 [#5271](https://github.com/apache/apisix/pull/5271)
- :sunrise: control API 暴露 upstream 配置 [#5259](https://github.com/apache/apisix/pull/5259)
- :sunrise: 支持在 etcd 少于半数节点不可用时成功启动 [#5158](https://github.com/apache/apisix/pull/5158)
- :sunrise: 支持 etcd 配置里面自定义 SNI [#5206](https://github.com/apache/apisix/pull/5206)

### Plugin

- :sunrise: 新增 Azure-functions 插件 [#5479](https://github.com/apache/apisix/pull/5479)
- :sunrise: kafka-logger 支持动态记录请求体 [#5501](https://github.com/apache/apisix/pull/5501)
- :sunrise: 新增 skywalking-logger 插件 [#5478](https://github.com/apache/apisix/pull/5478)
- :sunrise: 新增 datadog 插件 [#5372](https://github.com/apache/apisix/pull/5372)
- :sunrise: limit-* 系列插件，在 key 对应的值不存在时，回退到用客户端地址作为限流的 key [#5422](https://github.com/apache/apisix/pull/5422)
- :sunrise: limit-count 支持使用多个变量作为 key [#5378](https://github.com/apache/apisix/pull/5378)
- :sunrise: limit-conn 支持使用多个变量作为 key [#5354](https://github.com/apache/apisix/pull/5354)
- :sunrise: proxy-rewrite 支持改写 HTTP method [#5292](https://github.com/apache/apisix/pull/5292)
- :sunrise: limit-req 支持使用多个变量作为 key [#5302](https://github.com/apache/apisix/pull/5302)
- :sunrise: proxy-cache 支持基于内存的缓存机制 [#5028](https://github.com/apache/apisix/pull/5028)
- :sunrise: ext-plugin 避免发送重复的 conf 请求 [#5183](https://github.com/apache/apisix/pull/5183)
- :sunrise: 新增 ldap-auth 插件 [#3894](https://github.com/apache/apisix/pull/3894)

## 2.10.5

**这是一个 LTS 维护版本，您可以在 `release/2.10` 分支中看到 CHANGELOG。**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2105](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2105)

## 2.10.4

**这是一个 LTS 维护版本，您可以在 `release/2.10` 分支中看到 CHANGELOG。**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2104](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2104)

## 2.10.3

**这是一个 LTS 维护版本，您可以在 `release/2.10` 分支中看到 CHANGELOG。**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2103](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2103)

## 2.10.2

**这是一个 LTS 维护版本，您可以在 `release/2.10` 分支中看到 CHANGELOG。**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2102](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2102)

## 2.10.1

**这是一个 LTS 维护版本，您可以在 `release/2.10` 分支中看到 CHANGELOG。**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2101](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2101)

## 2.10.0

### Change

- 将 enable_debug 配置从 config.yaml 移到 debug.yaml [#5046](https://github.com/apache/apisix/pull/5046)
- 更改自定义 lua_shared_dict 配置的名称 [#5030](https://github.com/apache/apisix/pull/5030)
- 不再提供 APISIX 安装 shell 脚本 [#4985](https://github.com/apache/apisix/pull/4985)

### Core

- :sunrise: debug-mode 支持动态请求过滤 [#5012](https://github.com/apache/apisix/pull/5012)
- :sunrise: 支持注入逻辑到 APISIX 方法中 [#5068](https://github.com/apache/apisix/pull/5068)
- :sunrise: 支持配置 fallback SNI [#5000](https://github.com/apache/apisix/pull/5000)
- :sunrise: stream_route 支持在 IP 匹配中使用 CIDR [#4980](https://github.com/apache/apisix/pull/4980)
- :sunrise: 支持 route 从 service 中继承 hosts [#4977](https://github.com/apache/apisix/pull/4977)
- :sunrise: 改善数据面监听地址的配置 [#4856](https://github.com/apache/apisix/pull/4856)

### Plugin

- :sunrise: hmac-auth 支持校验请求体 [#5038](https://github.com/apache/apisix/pull/5038)
- :sunrise: proxy-mirror 支持控制镜像流量的比例 [#4965](https://github.com/apache/apisix/pull/4965)
- :sunrise: referer-restriction 增加黑名单和自定义信息 [#4916](https://github.com/apache/apisix/pull/4916)
- :sunrise: kafka-logger 增加 cluster 支持 [#4876](https://github.com/apache/apisix/pull/4876)
- :sunrise: kafka-logger 增加 required_acks 选项 [#4878](https://github.com/apache/apisix/pull/4878)
- :sunrise: uri-blocker 支持大小写无关的匹配 [#4868](https://github.com/apache/apisix/pull/4868)

### Bugfix

- radixtree_host_uri 路由更正匹配结果的 host [#5124](https://github.com/apache/apisix/pull/5124)
- radixtree_host_uri 路由更正匹配结果的 path [#5104](https://github.com/apache/apisix/pull/5104)
- Nacos 服务发现，区分处于不同 group/namespace 的同名 service [#5083](https://github.com/apache/apisix/pull/5083)
- Nacos 服务发现，当一个服务的地址获取失败后，继续处理剩下的服务 [#5112](https://github.com/apache/apisix/pull/5112)
- 匹配 SNI 时需要大小写无关 [#5074](https://github.com/apache/apisix/pull/5074)
- upstream 的 keepalive_pool 配置，缺省时不应覆盖默认的 keepalive 配置 [#5054](https://github.com/apache/apisix/pull/5054)
- DNS 服务发现，优先查询 SRV 记录 [#4992](https://github.com/apache/apisix/pull/4992)
- Consul 服务发现，重试前需等待一段时间 [#4979](https://github.com/apache/apisix/pull/4979)
- 当 upstream domain 背后的 IP 改变时，避免复制多余数据 [#4952](https://github.com/apache/apisix/pull/4952)
- 当 plugin_config 变化时，恢复之前被覆盖的配置 [#4888](https://github.com/apache/apisix/pull/4888)

## 2.9.0

### Change

- 为避免误解，将插件中的 balancer 方法改成 before_proxy [#4697](https://github.com/apache/apisix/pull/4697)

### Core

- :sunrise: 增大总 timer 数的限制 [#4843](https://github.com/apache/apisix/pull/4843)
- :sunrise: 移除禁止额外字段的检验，方便给 APISIX 做 A/B 测试 [#4797](https://github.com/apache/apisix/pull/4797)
- :sunrise: 支持在 arg 变量中使用 '-' (#4519) [#4676](https://github.com/apache/apisix/pull/4676)
- :sunrise: Admin API 拒绝错误的 proto 文件内容 [#4750](https://github.com/apache/apisix/pull/4750)

### Plugin

- :sunrise: ext-plugin 插件允许 Runner 查询请求信息 [#4835](https://github.com/apache/apisix/pull/4835)
- :sunrise: gzip 插件支持通过 * 匹配任意类型 [#4817](https://github.com/apache/apisix/pull/4817)
- :sunrise: 增加 real-ip 插件 [#4813](https://github.com/apache/apisix/pull/4813)
- :sunrise: limit-* 系列插件允许自定义请求拒绝信息 [#4808](https://github.com/apache/apisix/pull/4808)
- :sunrise: request-id 插件增加 snowflake 算法支持 [#4559](https://github.com/apache/apisix/pull/4559)
- :sunrise: 增加 authz-casbin 插件 [#4710](https://github.com/apache/apisix/pull/4710)
- :sunrise: error-log-logger 插件增加 skywalking 后端 [#4633](https://github.com/apache/apisix/pull/4633)
- :sunrise: ext-plugin 插件在发送配置时会额外发送一个 idempotent key [#4736](https://github.com/apache/apisix/pull/4736)

### Bugfix

- 避免特定条件下缓存过期的全局规则 [#4867](https://github.com/apache/apisix/pull/4867)
- grpc-transcode 插件支持嵌套信息 [#4859](https://github.com/apache/apisix/pull/4859)
- authz-keycloak 插件避免当 lazy_load_path 为 false 且没有配置 permissions 时出错 [#4845](https://github.com/apache/apisix/pull/4845)
- proxy-cache 插件保持 cache_method 配置和 nginx's proxy_cache_methods 一致 [#4814](https://github.com/apache/apisix/pull/4814)
- Admin API 确保 PATCH with sub path 时也能注入 updatetime [#4765](https://github.com/apache/apisix/pull/4765)
- Admin API 更新 consumer 时校验 username [#4756](https://github.com/apache/apisix/pull/4756)
- error-log-logger 插件避免发送过期的错误日志 [#4690](https://github.com/apache/apisix/pull/4690)
- grpc-transcode 插件支持 enum 类型 [#4706](https://github.com/apache/apisix/pull/4706)
- 当非 HEAD/GET 请求触发 500 错误时，会被错误转成 405 [#4696](https://github.com/apache/apisix/pull/4696)

## 2.8.0

### Change

- 如果启用 stream proxy，默认将不再一并启用 HTTP proxy 功能 [#4580](https://github.com/apache/apisix/pull/4580)

### Core

- :sunrise: 允许用户自定义 balancer [#4605](https://github.com/apache/apisix/pull/4605)
- :sunrise: upstream 中添加 retry_timeout，类似于 Nginx 的 proxy_next_upstream_timeout [#4574](https://github.com/apache/apisix/pull/4574)
- :sunrise: 允许在 balancer_by_lua 中运行插件 [#4549](https://github.com/apache/apisix/pull/4549)
- :sunrise: 允许给 upstream 指定单独的连接池 [#4506](https://github.com/apache/apisix/pull/4506)
- :sunrise: etcd 连接开启健康检查 [#4191](https://github.com/apache/apisix/pull/4191)

### Plugin

- :sunrise: 增加 gzip 插件 [#4640](https://github.com/apache/apisix/pull/4640)
- :sunrise: 增加 ua-restriction 插件来拒绝爬虫请求 [#4587](https://github.com/apache/apisix/pull/4587)
- :sunrise: stream 模块增加 ip-restriction 插件 [#4602](https://github.com/apache/apisix/pull/4602)
- :sunrise: stream 模块增加 limit-conn 插件 [#4515](https://github.com/apache/apisix/pull/4515)
- :sunrise: 将 ext-plugin 的超时提升到 60s [#4557](https://github.com/apache/apisix/pull/4557)
- :sunrise: key-auth 支持从 query string 中获取 key [#4490](https://github.com/apache/apisix/pull/4490)
- :sunrise: kafka-logger 支持通过 admin API 设置日志格式 [#4483](https://github.com/apache/apisix/pull/4483)

### Bugfix

- 修复 stream proxy 的 SNI router 在 session 复用中不可用的问题 [#4607](https://github.com/apache/apisix/pull/4607)
- 修复 limit-conn 同时在全局和 route 中指定会出错的问题 [#4585](https://github.com/apache/apisix/pull/4585)
- 修复 Admin API 中检查 proto 引用关系的错误 [#4575](https://github.com/apache/apisix/pull/4575)
- 修复 skywalking 同时在全局和 route 中指定会出错的问题 [#4589](https://github.com/apache/apisix/pull/4589)
- 调用 `ctx.var.cookie_*` 时如果没有找到 cookie 不再报错 [#4564](https://github.com/apache/apisix/pull/4564)
- 修复 request-id 同时在全局和 route 中指定会出错的问题 [#4479](https://github.com/apache/apisix/pull/4479)

## 2.7.0

### Change

- 修改 metadata_schema 校验方式，让它跟其他 schema 一致 [#4381](https://github.com/apache/apisix/pull/4381)
- 移除 echo 插件的 auth_value 字段 [#4055](https://github.com/apache/apisix/pull/4055)
- 更正 Admin API count 字段的计算，并把它的类型变成 integer [#4385](https://github.com/apache/apisix/pull/4385)

### Core

- :sunrise: TCP 代理支持客户端证书校验 [#4445](https://github.com/apache/apisix/pull/4445)
- :sunrise: TCP 代理支持接收 TLS over TCP 连接 [#4409](https://github.com/apache/apisix/pull/4409)
- :sunrise: TCP/UDP 代理上游配置支持用域名 [#4386](https://github.com/apache/apisix/pull/4386)
- :sunrise: CLI 中封装 nginx quit 操作 [#4360](https://github.com/apache/apisix/pull/4360)
- :sunrise: 允许在 route 配置上游超时时间 [#4340](https://github.com/apache/apisix/pull/4340)
- :sunrise: Nacos 服务发现支持 group 参数 [#4325](https://github.com/apache/apisix/pull/4325)
- :sunrise: Nacos 服务发现支持 namespace 参数 [#4313](https://github.com/apache/apisix/pull/4313)

### Plugin

- :sunrise: client-control 允许动态设置 client_max_body_size [#4423](https://github.com/apache/apisix/pull/4423)
- :sunrise: ext-plugin 使用 SIGTERM 结束 runner [#4367](https://github.com/apache/apisix/pull/4367)
- :sunrise: limit-req 增加 nodelay 参数 [#4395](https://github.com/apache/apisix/pull/4395)
- :sunrise: mqtt-proxy 允许配置域名 [#4391](https://github.com/apache/apisix/pull/4391)
- :sunrise: redirect 支持带上 query string [#4298](https://github.com/apache/apisix/pull/4298)

### Bugfix

- 修复客户端断开连接导致的内存泄漏 [#4405](https://github.com/apache/apisix/pull/4405)
- 修复处理 etcd 响应时有一个地方没有检查 res.body.error 的问题 [#4371](https://github.com/apache/apisix/pull/4371)
- 修复 ext-plugin 插件 token 过期后没有刷新 token 的问题 [#4345](https://github.com/apache/apisix/pull/4345)
- 修复 ext-plugin 插件没有传递环境变量的问题 [#4349](https://github.com/apache/apisix/pull/4349)
- 修复插件热加载时，插件可能不会重新加载的问题 [#4319](https://github.com/apache/apisix/pull/4319)

## 2.6.0

### Change

- 更改 prometheus 里面关于 latency 的指标的 label [#3993](https://github.com/apache/apisix/pull/3993)
- 修改 prometheus 默认端口，不再暴露到数据面的端口上 [#3994](https://github.com/apache/apisix/pull/3994)
- limit-count 里面如果使用 redis cluster，需要指定名称 [#3910](https://github.com/apache/apisix/pull/3910)
- 不再支持 OpenResty 1.15 [#3960](https://github.com/apache/apisix/pull/3960)

### Core

- :sunrise: 允许 pass_host 为 node 时，upstream 配置多个节点 [#4208](https://github.com/apache/apisix/pull/4208)
- :sunrise: 自定义 500 错误页 [#4164](https://github.com/apache/apisix/pull/4164)
- :sunrise: stream_route 中支持 upstream_id [#4121](https://github.com/apache/apisix/pull/4121)
- :sunrise: 支持客户端证书认证 [#4034](https://github.com/apache/apisix/pull/4034)
- :sunrise: 实验性支持 nacos 服务发现 [#3820](https://github.com/apache/apisix/pull/3820)
- :sunrise: 给 tcp.sock.connect 打补丁，采用配置的 DNS resolver [#4114](https://github.com/apache/apisix/pull/4114)

### Plugin

- :sunrise: redirect 插件，支持编码 uri [#4244](https://github.com/apache/apisix/pull/4244)
- :sunrise: key-auth 插件：支持自定义鉴权头 [#4013](https://github.com/apache/apisix/pull/4013)
- :sunrise: response-rewrite 插件：允许在 header 里面使用变量 [#4194](https://github.com/apache/apisix/pull/4194)
- :sunrise: 实现 ext-plugin 第一版，APISIX 现在支持使用其他语言编写自定义插件 [#4183](https://github.com/apache/apisix/pull/4183)

### Bugfix

- 支持 IPv6 DNS resolver [#4242](https://github.com/apache/apisix/pull/4242)
- 修复被动健康检查可能重复报告的问题 [#4116](https://github.com/apache/apisix/pull/4116)
- 修复 traffic-split 中偶发的规则紊乱 [#4092](https://github.com/apache/apisix/pull/4092)
- 修复带域名的 upstream 配置的访问问题 [#4061](https://github.com/apache/apisix/pull/4061)
- 修复 2.5 版本的 APISIX 无法识别之前版本的 route 配置的问题 [#4056](https://github.com/apache/apisix/pull/4056)
- standalone 模式下，启动程序时应该可以读取配置 [#4027](https://github.com/apache/apisix/pull/4027)
- limit-count 插件 redis 模式下原子化计数操作 [#3991](https://github.com/apache/apisix/pull/3991)

## 2.5.0

### Change

- 更改 zipkin 插件的 span 类型 [#3877](https://github.com/apache/apisix/pull/3877)

### Core

- :sunrise: 支持 etcd 客户端证书校验 [#3905](https://github.com/apache/apisix/pull/3905)
- :sunrise: 支持表达式使用“或”和“非”的逻辑 [#3809](https://github.com/apache/apisix/pull/3809)
- :sunrise: 默认启动时会同步 etcd 配置 [#3799](https://github.com/apache/apisix/pull/3799)
- :sunrise: 负载均衡支持节点优先级 [#3755](https://github.com/apache/apisix/pull/3755)
- :sunrise: 服务发现提供了一系列 control API [#3742](https://github.com/apache/apisix/pull/3742)

### Plugin

- :sunrise: 允许热更新 skywalking 插件配置，并允许配置上报间隔 [#3925](https://github.com/apache/apisix/pull/3925)
- :sunrise: consumer-restriction 支持 HTTP method 级别的白名单配置 [#3691](https://github.com/apache/apisix/pull/3691)
- :sunrise: cors 插件支持通过正则表达式匹配 Origin [#3839](https://github.com/apache/apisix/pull/3839)
- :sunrise: response-rewrite 插件支持条件改写 [#3577](https://github.com/apache/apisix/pull/3577)

### Bugfix

- error-log-logger 插件需要在每个进程中上报日志 [#3912](https://github.com/apache/apisix/pull/3912)
- 当使用 snippet 引入 Nginx server 段配置时，确保内置 server 是默认 server [#3907](https://github.com/apache/apisix/pull/3907)
- 修复 traffic-split 插件通过 upstream_id 绑定上游的问题 [#3842](https://github.com/apache/apisix/pull/3842)
- 修复 ssl_trusted_certificate 配置项的校验 [#3832](https://github.com/apache/apisix/pull/3832)
- 启用 proxy-cache 时，避免覆盖到其他路由缓存相关的响应头 [#3789](https://github.com/apache/apisix/pull/3789)
- 解决 macOS 下无法 `make deps` 的问题 [#3718](https://github.com/apache/apisix/pull/3718)

## 2.4.0

### Change

- 插件暴露的公共 API 将默认不再执行全局插件 [#3396](https://github.com/apache/apisix/pull/3396)
- DNS 记录缓存时间默认按 TTL 设置 [#3530](https://github.com/apache/apisix/pull/3530)

### Core

- :sunrise: 支持 DNS SRV 记录 [#3686](https://github.com/apache/apisix/pull/3686)
- :sunrise: 新的 DNS 服务发现模块 [#3629](https://github.com/apache/apisix/pull/3629)
- :sunrise: 支持 Consul HTTP 接口服务发现模块 [#3615](https://github.com/apache/apisix/pull/3615)
- :sunrise: 支持插件复用 [#3567](https://github.com/apache/apisix/pull/3567)
- :sunrise: 支持 plaintext HTTP2 [#3547](https://github.com/apache/apisix/pull/3547)
- :sunrise: 支持 DNS AAAA 记录 [#3484](https://github.com/apache/apisix/pull/3484)

### Plugin

- :sunrise: traffic-split 插件支持 upstream_id [#3512](https://github.com/apache/apisix/pull/3512)
- :sunrise: zipkin 插件 b3 请求头 [#3551](https://github.com/apache/apisix/pull/3551)

### Bugfix

- 一致性 hash 负载均衡确保重试所有节点 [#3651](https://github.com/apache/apisix/pull/3651)
- 当 route 绑定 service 后仍能执行 script [#3678](https://github.com/apache/apisix/pull/3678)
- 应当依赖 openssl111 [#3603](https://github.com/apache/apisix/pull/3603)
- zipkin 避免缓存请求特定的数据 [#3522](https://github.com/apache/apisix/pull/3522)

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/13)

## 2.3.0

### Change

- 默认使用 LuaJIT 运行命令行 [#3335](https://github.com/apache/apisix/pull/3335)
- 命令行采用 luasocket 而不是 curl 访问 etcd [#2965](https://github.com/apache/apisix/pull/2965)

### Core

- :sunrise: 命令行中访问 etcd 可以禁用 HTTPS 检验 [#3415](https://github.com/apache/apisix/pull/3415)
- :sunrise: 添加 etcd 无法连接时的 Chaos 测试 [#3404](https://github.com/apache/apisix/pull/3404)
- :sunrise: ewma 负载均衡算法更新 [#3300](https://github.com/apache/apisix/pull/3300)
- :sunrise: 允许在 Upstream 中配置 HTTPS scheme 来跟 HTTPS 后端通信 [#3430](https://github.com/apache/apisix/pull/3430)
- :sunrise: 允许自定义 lua_package_path & lua_package_cpath [#3417](https://github.com/apache/apisix/pull/3417)
- :sunrise: HTTPS 代理时传递 SNI [#3420](https://github.com/apache/apisix/pull/3420)
- :sunrise: 支持 gRPCS [#3411](https://github.com/apache/apisix/pull/3411)
- :sunrise: 支持通过 control API 获得健康检查状态 [#3345](https://github.com/apache/apisix/pull/3345)
- :sunrise: 支持代理 HTTP 到 dubbo 后端 [#3224](https://github.com/apache/apisix/pull/3224)
- :sunrise: 支持最少连接负载均衡算法 [#3304](https://github.com/apache/apisix/pull/3304)

### Plugin

- :sunrise: kafka-logger 支持复用 kafka 生产者对象 [#3429](https://github.com/apache/apisix/pull/3429)
- :sunrise: authz-keycloak 支持动态 scope & resource 映射 [#3308](https://github.com/apache/apisix/pull/3308)
- :sunrise: proxy-rewrite 支持在域名中带端口 [#3428](https://github.com/apache/apisix/pull/3428)
- :sunrise: fault-injection 支持通过变量条件动态做错误注入 [#3363](https://github.com/apache/apisix/pull/3363)

### Bugfix

- 修复 standalone 下 consumer 的 id 跟 username 可以不一致的问题 [#3394](https://github.com/apache/apisix/pull/3394)
- gRPC 中可以用 upstream_id & consumer [#3387](https://github.com/apache/apisix/pull/3387)
- 修复没有匹配规则时命中 global rule 报错的问题 [#3332](https://github.com/apache/apisix/pull/3332)
- 避免缓存过期的服务发现得到的节点 [#3295](https://github.com/apache/apisix/pull/3295)
- 应该在 access 阶段创建 health checker [#3240](https://github.com/apache/apisix/pull/3240)
- 修复 chash 负载均衡算法时重试的问题 [#2676](https://github.com/apache/apisix/pull/2676)

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/12)

## 2.2.0

### Change

- 默认不启用 node-status 插件 [#2968](https://github.com/apache/apisix/pull/2968)
- upstreeam 配置中不再允许使用 k8s_deployment_info [#3098](https://github.com/apache/apisix/pull/3098)
- 默认不再匹配路由中以 ':' 开头的参数变量 [#3154](https://github.com/apache/apisix/pull/3154)

### Core

- :sunrise: 允许一个 consumer 关联多个认证插件 [#2898](https://github.com/apache/apisix/pull/2898)
- :sunrise: 增加 etcd 重试间隔，并允许配置 [#2977](https://github.com/apache/apisix/pull/2977)
- :sunrise: 允许启用或禁用 route [#2943](https://github.com/apache/apisix/pull/2943)
- :sunrise: 允许通过 graphql 属性进行路由 [#2964](https://github.com/apache/apisix/pull/2964)
- :sunrise: 共享 etcd 鉴权 token [#2932](https://github.com/apache/apisix/pull/2932)
- :sunrise: 新增 control API [#3048](https://github.com/apache/apisix/pull/3048)

### Plugin

- :sunrise: limt-count 中使用 'remote_addr' 作为默认 key [#2927](https://github.com/apache/apisix/pull/2927)
- :sunrise: 支持在 fault-injection 的 abort.body 中使用变量 [#2986](https://github.com/apache/apisix/pull/2986)
- :sunrise: 新增插件 `server-info` [#2926](https://github.com/apache/apisix/pull/2926)
- :sunrise: 增加 batch process 指标 [#3070](https://github.com/apache/apisix/pull/3070)
- :sunrise: 新增 traffic-split 插件 [#2935](https://github.com/apache/apisix/pull/2935)
- :sunrise: proxy-rewrite 支持在 header 中使用变量 [#3144](https://github.com/apache/apisix/pull/3144)
- :sunrise: openid-connect 插件增加更多配置项 [#2903](https://github.com/apache/apisix/pull/2903)
- :sunrise: proxy-rewrite 支持在 upstream_uri 中使用变量 [#3139](https://github.com/apache/apisix/pull/3139)

### Bugfix

- basic-auth 应该在 rewrite phase 执行 [#2905](https://github.com/apache/apisix/pull/2905)
- http/udp-logger 中插件配置运行时变更没有生效 [#2901](https://github.com/apache/apisix/pull/2901)
- 修复 limit-conn 对象没有被正确释放的问题 [#2465](https://github.com/apache/apisix/pull/2465)
- 修复自动生成的 id 可能重复的问题 [#3003](https://github.com/apache/apisix/pull/3003)
- 修复 OpenResty 1.19 下 ctx 互相影响的问题。**对于使用 OpenResty 1.19 的用户，请尽快升级到该版本。** [#3105](https://github.com/apache/apisix/pull/3105)
- 修复 route.vars 字段的校验 [#3124](https://github.com/apache/apisix/pull/3124)

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/10)

## 2.1.0

### Core

- :sunrise: **支持使用环境变量来配置参数。** [#2743](https://github.com/apache/apisix/pull/2743)
- :sunrise: **支持使用 TLS 来连接 etcd.** [#2548](https://github.com/apache/apisix/pull/2548)
- 自动生成对象的创建和更新时间。[#2740](https://github.com/apache/apisix/pull/2740)
- 在上游中开启 websocket 时，增加日志来提示此功能即将废弃。[#2691](https://github.com/apache/apisix/pull/2691)
- 增加日志来提示 consumer id 即将废弃。[#2829](https://github.com/apache/apisix/pull/2829)
- 增加 `X-APISIX-Upstream-Status` 头来区分 5xx 错误来自上游还是 APISIX 自身。[#2817](https://github.com/apache/apisix/pull/2817)
- 支持 Nginx 配置片段。[#2803](https://github.com/apache/apisix/pull/2803)

### Plugin

- :sunrise: **升级协议来 Apache Skywalking 8.0**[#2389](https://github.com/apache/apisix/pull/2389). 这个版本只支持 skywalking 8.0 协议。此插件默认关闭，需要修改 config.yaml 来开启。这是不向下兼容的修改。
- :sunrise: 新增阿里云 sls 日志服务插件。[#2169](https://github.com/apache/apisix/issues/2169)
- proxy-cache: cache_zone 字段改为可选。[#2776](https://github.com/apache/apisix/pull/2776)
- 在数据平面校验插件的配置。[#2856](https://github.com/apache/apisix/pull/2856)

### Bugfix

- :bug: fix(etcd): 处理 etcd compaction.[#2687](https://github.com/apache/apisix/pull/2687)
- 将 `conf/cert` 中的测试证书移动到 `t/certs` 目录中，并且默认关闭 SSL。这是不向下兼容的修改。 [#2112](https://github.com/apache/apisix/pull/2112)
- 检查 decrypt key 来阻止 lua thread 中断。 [#2815](https://github.com/apache/apisix/pull/2815)

### 不向下兼容特性预告

- 在 2.3 发布版本中，consumer 将只支持用户名，废弃 id，consumer 需要在 etcd 中手工清理掉 id 字段，不然使用时 schema 校验会报错
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

### Plugin

- :sunrise: **增加 AK/SK(HMAC) 认证插件。**[#2192](https://github.com/apache/apisix/pull/2192)
- :sunrise: 增加 referer-restriction 插件。[#2352](https://github.com/apache/apisix/pull/2352)
- `limit-count` 插件支持 `redis` cluster。[#2406](https://github.com/apache/apisix/pull/2406)
- proxy-cache 插件支持存储临时文件。[#2317](https://github.com/apache/apisix/pull/2317)
- http-logger 插件支持通过 admin API 来指定文件格式。[#2309](https://github.com/apache/apisix/pull/2309)

### Bugfix

- :bug: **`高优先级`** 当数据平面接收到删除某一个资源 (路由、上游等) 的指令时，没有正确的清理缓存，导致存在的资源也会找不到。这个问题在长时间、频繁删除操作的情况下才会出现。[#2168](https://github.com/apache/apisix/pull/2168)
- 修复路由优先级不生效的问题。[#2447](https://github.com/apache/apisix/pull/2447)
- 在 `init_worker` 阶段设置随机数，而不是 `init` 阶段。[#2357](https://github.com/apache/apisix/pull/2357)
- 删除 jwt 插件中不支持的算法。[#2356](https://github.com/apache/apisix/pull/2356)
- 当重定向插件的 `http_to_https` 开启时，返回正确的响应码。[#2311](https://github.com/apache/apisix/pull/2311)

更多的变动可以参考[里程碑](https://github.com/apache/apisix/milestone/7)

### CVE

- 修复 Admin API 默认访问令牌漏洞

## 1.5.0

### Core

- Admin API：支持使用 SSL 证书进行身份验证。[1747](https://github.com/apache/apisix/pull/1747)
- Admin API：同时支持标准的 PATCH 和子路径 PATCH。[1930](https://github.com/apache/apisix/pull/1930)
- HealthCheck：支持自定义检查端口。[1914](https://github.com/apache/apisix/pull/1914)
- Upstream：支持禁用 `Nginx` 默认重试机制。[1919](https://github.com/apache/apisix/pull/1919)
- URI：支持以配置方式删除 `URI` 末尾的 `/` 符号。[1766](https://github.com/apache/apisix/pull/1766)

### New Plugin

- :sunrise: **新增 请求验证器 插件** [1709](https://github.com/apache/apisix/pull/1709)

### Improvements

- 变更：nginx `worker_shutdown_timeout` 配置默认值由 `3s` 变更为推荐值 `240s`。[1883](https://github.com/apache/apisix/pull/1883)
- 变更：`healthcheck` 超时时间类型 由 `integer` 变更为 `number`。[1892](https://github.com/apache/apisix/pull/1892)
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
- 文档：删除 `k8s` 文档中不必要的配置。[1891](https://github.com/apache/apisix/pull/1891)

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
- 实现完成 `sys logger` 插件。[#1414](https://github.com/apache/incubator-apisix/pull/1414)

## 1.2.0

1.2 版本在内核以及插件上带来了非常多的更新。

### Core

- :sunrise: **支持 etcd 集群**. [#1283](https://github.com/apache/incubator-apisix/pull/1283)
- 默认使用本地 DNS resolver，这对于 k8s 环境更加友好。[#1387](https://github.com/apache/incubator-apisix/pull/1387)
- 支持在 `header_filter`、`body_filter` 和 `log` 阶段运行全局插件。[#1364](https://github.com/apache/incubator-apisix/pull/1364)
- 将目录 `lua/apisix` 修改为 `apisix`(**不向下兼容**). [#1351](https://github.com/apache/incubator-apisix/pull/1351)
- 增加 dashboard 子模块。[#1360](https://github.com/apache/incubator-apisix/pull/1360)
- 允许自定义共享字典。[#1367](https://github.com/apache/incubator-apisix/pull/1367)

### Plugin

- :sunrise: **新增 Apache Kafka 插件**. [#1312](https://github.com/apache/incubator-apisix/pull/1312)
- :sunrise: **新增 CORS 插件**. [#1327](https://github.com/apache/incubator-apisix/pull/1327)
- :sunrise: **新增 TCP logger 插件**. [#1221](https://github.com/apache/incubator-apisix/pull/1221)
- :sunrise: **新增 UDP logger 插件**. [1070](https://github.com/apache/incubator-apisix/pull/1070)
- :sunrise: **新增 proxy mirror 插件**. [#1288](https://github.com/apache/incubator-apisix/pull/1288)
- :sunrise: **新增 proxy cache 插件**. [#1153](https://github.com/apache/incubator-apisix/pull/1153)
- 在 proxy-rewrite 插件中废弃 websocket 开关 (**不向下兼容**). [1332](https://github.com/apache/incubator-apisix/pull/1332)
- OAuth 插件中增加基于公钥的自省支持。[#1266](https://github.com/apache/incubator-apisix/pull/1266)
- response-rewrite 插件通过 base64 来支持传输二进制数据。[#1381](https://github.com/apache/incubator-apisix/pull/1381)
- gRPC 转码插件支持 `deadline`. [#1149](https://github.com/apache/incubator-apisix/pull/1149)
- limit count 插件支持 redis 权限认证。[#1150](https://github.com/apache/incubator-apisix/pull/1150)
- Zipkin 插件支持名字和本地服务器 ip 的记录。[#1386](https://github.com/apache/incubator-apisix/pull/1386)
- Wolf-Rbac 插件增加 `change_pwd` 和 `user_info` 参数。[#1204](https://github.com/apache/incubator-apisix/pull/1204)

### Admin API

- :sunrise: 对调用 Admin API 增加 key-auth 权限认证 (**not backward compatible**). [#1169](https://github.com/apache/incubator-apisix/pull/1169)
- 隐藏 SSL 私钥的返回值。[#1240](https://github.com/apache/incubator-apisix/pull/1240)

### Bugfix

- 在复用 table 之前遗漏了对数据的清理 (**会引发内存泄漏**). [#1134](https://github.com/apache/incubator-apisix/pull/1134)
- 如果 yaml 中路由非法就打印警告信息。[#1141](https://github.com/apache/incubator-apisix/pull/1141)
- 使用空字符串替代空的 balancer IP. [#1166](https://github.com/apache/incubator-apisix/pull/1166)
- 修改 node-status 和 heartbeat 插件没有 schema 的问题。[#1249](https://github.com/apache/incubator-apisix/pull/1249)
- basic-auth 增加 required 字段。[#1251](https://github.com/apache/incubator-apisix/pull/1251)
- 检查上游合法节点的个数。[#1292](https://github.com/apache/incubator-apisix/pull/1292)

## 1.1.0

这个版本主要是加强代码的稳定性，以及增加更多的文档。

### Core

- 每次跑测试用例都指定 perl 包含路径。 [#1097](https://github.com/apache/incubator-apisix/pull/1097)
- 增加对代理协议的支持。 [#1113](https://github.com/apache/incubator-apisix/pull/1113)
- 增加用于校验 nginx.conf 的命令。 [#1112](https://github.com/apache/incubator-apisix/pull/1112)
- 支持「nginx 最多可以打开文件数」可配置，并增大其默认配置。[#1105](https://github.com/apache/incubator-apisix/pull/1105) [#1098](https://github.com/apache/incubator-apisix/pull/1098)
- 优化日志模块。 [#1093](https://github.com/apache/incubator-apisix/pull/1093)
- 支持 SO_REUSEPORT。 [#1085](https://github.com/apache/incubator-apisix/pull/1085)

### Doc

- 增加 Grafana 元数据下载链接。[#1119](https://github.com/apache/incubator-apisix/pull/1119)
- 更新 README.md。 [#1118](https://github.com/apache/incubator-apisix/pull/1118)
- 增加 wolf-rbac 插件说明文档 [#1116](https://github.com/apache/incubator-apisix/pull/1116)
- 更新 rpm 下载链接。 [#1108](https://github.com/apache/incubator-apisix/pull/1108)
- 增加更多英文文章链接。 [#1092](https://github.com/apache/incubator-apisix/pull/1092)
- 增加文档贡献指引。 [#1086](https://github.com/apache/incubator-apisix/pull/1086)
- 检查更新「快速上手」文档。 [#1084](https://github.com/apache/incubator-apisix/pull/1084)
- 检查更新「插件开发指南」。 [#1078](https://github.com/apache/incubator-apisix/pull/1078)
- 更新 admin-api-cn.md。 [#1067](https://github.com/apache/incubator-apisix/pull/1067)
- 更新 architecture-design-cn.md。 [#1065](https://github.com/apache/incubator-apisix/pull/1065)

### CI

- 移除不再必须的补丁。 [#1090](https://github.com/apache/incubator-apisix/pull/1090)
- 修复使用 luarocks 安装时路径错误问题。[#1068](https://github.com/apache/incubator-apisix/pull/1068)
- 为 luarocks 安装专门配置一个 travis 进行回归测试。 [#1063](https://github.com/apache/incubator-apisix/pull/1063)

### Plugins

- 在「节点状态」插件使用 nginx 内部请求替换原来的外部请求。 [#1109](https://github.com/apache/incubator-apisix/pull/1109)
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

这个版本带来很多新特性，比如支持使用 Tengine 运行 APISIX，增加了对开发人员更友好的高级调试模式，还有新的 URI 重定向插件等。

### Core

- :sunrise: 支持使用 Tengine 运行 APISIX。 [#683](https://github.com/apache/incubator-apisix/pull/683)
- :sunrise: 启用 HTTP2 并支持设置 ssl_protocols。 [#663](https://github.com/apache/incubator-apisix/pull/663)
- :sunrise: 增加高级调试模式，可在不重启的服务的情况下动态打印指定模块方法的请求参数或返回值。[#614](https://github.com/apache/incubator-apisix/pull/641)
- 安装程序增加了仪表盘开关，支持用户自主选择是否安装仪表板程序。 [#686](https://github.com/apache/incubator-apisix/pull/686)
- 取消对 R3 路由的支持，并移除 R3 路由模块。 [#725](https://github.com/apache/incubator-apisix/pull/725)

### Plugins

- :sunrise: **[Redirect URI](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/redirect.md)**：URI 重定向插件。 [#732](https://github.com/apache/incubator-apisix/pull/732)
- [Proxy Rewrite](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/proxy-rewrite.md)：支持 `header` 删除功能。 [#658](https://github.com/apache/incubator-apisix/pull/658)
- [Limit Count](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/limit-count.md)：通过 `Redis Server` 聚合 `APISIX` 节点之间将共享流量限速结果，实现集群流量限速。[#624](https://github.com/apache/incubator-apisix/pull/624)

### lua-resty-*

- lua-resty-radixtree
    - 支持将`host + uri`作为索引。
- lua-resty-jsonschema
    - 该扩展作用是 JSON 数据验证器，用于替换现有的 `lua-rapidjson` 扩展。

### Bugfix

- 在多个使用者的情况下，`key-auth` 插件无法正确运行。 [#826](https://github.com/apache/incubator-apisix/pull/826)
- 无法在 `API Server` 中获取 `serverless`插件配置。 [#787](https://github.com/apache/incubator-apisix/pull/787)
- 解决使用 `proxy-write` 重写 URI 时 GET 参数丢失问题。 [#642](https://github.com/apache/incubator-apisix/pull/642)
- `Zipkin` 插件未将跟踪数据设置为请求头。[#715](https://github.com/apache/incubator-apisix/pull/715)
- 使用本地文件作为配置中心时，跳过 etcd 初始化。 [#737](https://github.com/apache/incubator-apisix/pull/737)
- 在 APISIX CLI 中跳过 luajit 环境的`check cjson`。[#652](https://github.com/apache/incubator-apisix/pull/652)
- 配置 `Upstream` 时，选择 `balancer` 类型为 `chash` 时，支持更多 Nginx 内置变量作为计算 key。 [#775](https://github.com/apache/incubator-apisix/pull/775)

### Dependencies

- 使用 `lua-resty-jsonschema` 全局替换 `lua-rapidjson` 扩展，`lua-resty-jsonschema` 解析速度更快，更容易编译。

## 0.8.0

> Released on 2019/09/30

这个版本带来很多新的特性，比如四层协议的代理，支持 MQTT 协议代理，以及对 ARM 平台的支持，和代理改写插件等。

### Core

- :sunrise: **[增加单机模式](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/deployment-modes.md#Standalone)**: 使用 yaml 配置文件来更新 APISIX 的配置，这对于 kubernetes 更加友好。 [#464](https://github.com/apache/incubator-apisix/pull/464)
- :sunrise: **[支持 stream 代理](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest/stream-proxy.md)**. [#513](https://github.com/apache/incubator-apisix/pull/513)
- :sunrise: 支持[在 consumer 上绑定插件](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest/terminology/consumer.md). [#544](https://github.com/apache/incubator-apisix/pull/544)
- 上游增加对域名的支持，而不仅是 IP。[#522](https://github.com/apache/incubator-apisix/pull/522)
- 当上游节点的权重为 0 时自动忽略。[#536](https://github.com/apache/incubator-apisix/pull/536)

### Plugins

- :sunrise: **[MQTT 代理](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/mqtt-proxy.md)**: 支持用 `client_id` 对 MQTT 进行负载均衡，同时支持 MQTT 3.1 和 5.0 两个协议标准。 [#513](https://github.com/apache/incubator-apisix/pull/513)
- [proxy-rewrite](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/proxy-rewrite.md): 对代理到上游的请求进行改写，包括 host, uri 和 schema。 [#594](https://github.com/apache/incubator-apisix/pull/594)

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

- 健康检查：修复在多 worker 下运行时健康检查 checker 的名字错误。 [#568](https://github.com/apache/incubator-apisix/issues/568)

### Dependencies

- 把 `lua-tinyyaml` 从源码中移除，通过 Luarocks 来安装。

## 0.7.0

> Released on 2019/09/06

这个版本带来很多新的特性，比如 IP 黑白名单、gPRC 协议转换、支持 IPv6、对接 IdP（身份认证提供商）服务、serverless、默认路由修改为 radix tree（**不向下兼容**）等。

### Core

- :sunrise: **[gRPC 协议转换](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/grpc-transcode.md)**: 支持 gRPC 协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API. [#395](https://github.com/apache/incubator-apisix/issues/395)
- :sunrise: **[radix tree 路由](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//router-radixtree.md)**: 默认的路由器更改为 radix tree，支持把 uri、host、cookie、请求头、请求参数、Nginx 内置变量等作为路由的条件，并支持等于、大于、小于等常见操作符，更加强大和灵活。**需要注意的是，这个改动不向下兼容，所有使用历史版本的用户，需要手动修改路由才能正常使用**。[#414](https://github.com/apache/incubator-apisix/issues/414)
- 动态上游支持更多的参数，可以指定上游的 uri 和 host，以及是否开启 websocket. [#451](https://github.com/apache/incubator-apisix/pull/451)
- 支持从 `ctx.var` 中直接获取 cookie 中的值。[#449](https://github.com/apache/incubator-apisix/pull/449)
- 路由支持 IPv6. [#331](https://github.com/apache/incubator-apisix/issues/331)

### Plugins

- :sunrise: **[serverless](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/serverless.md)**: 支持 serverless，用户可以把任意 Lua 函数动态的在网关节点上运行。用户也可以把这个功能当做是轻量级的插件来使用。[#86](https://github.com/apache/incubator-apisix/pull/86)
- :sunrise: **IdP 支持**: 支持外部的身份认证服务，比如 Auth0，okta 等，用户可以借此来对接 Oauth2.0 等认证方式。 [#447](https://github.com/apache/incubator-apisix/pull/447)
- [限流限速](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/limit-conn.md)支持更多的限制 key，比如 X-Forwarded-For 和 X-Real-IP，并且允许用户把 Nginx 变量、请求头和请求参数作为 key. [#228](https://github.com/apache/incubator-apisix/issues/228)
- [IP 黑白名单](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/ip-restriction.md) 支持 IP 黑白名单，提供更高的安全性。[#398](https://github.com/apache/incubator-apisix/pull/398)

### CLI

- 增加 `version` 指令，获取 APISIX 的版本号。[#420](https://github.com/apache/incubator-apisix/issues/420)

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

- :sunrise: **[健康检查和服务熔断](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest/tutorials/health-check.md)**: 对上游节点开启健康检查，智能判断服务状态进行熔断和连接。[#249](https://github.com/apache/incubator-apisix/pull/249)
- 阻止 ReDoS(Regular expression Denial of Service). [#252](https://github.com/apache/incubator-apisix/pull/250)
- 支持 debug 模式。[#319](https://github.com/apache/incubator-apisix/pull/319)
- 允许自定义路由。[#364](https://github.com/apache/incubator-apisix/pull/364)
- 路由支持 host 和 uri 的组合。[#325](https://github.com/apache/incubator-apisix/pull/325)
- 允许在 balance 阶段注入插件。[#299](https://github.com/apache/incubator-apisix/pull/299)
- 为 upstream 和 service 在 schema 中增加描述信息。[#289](https://github.com/apache/incubator-apisix/pull/289)

### Plugins

- :sunrise: **[分布式追踪 OpenTracing](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/zipkin.md)**: 支持 Zipkin 和 Apache SkyWalking. [#304](https://github.com/apache/incubator-apisix/pull/304)
- [JWT 认证](https://github.com/apache/incubator-apisix/blob/master/docs/zh/latest//plugins/jwt-auth.md). [#303](https://github.com/apache/incubator-apisix/pull/303)

### CLI

- `allow` 指令中支持多个 ip 地址。[#340](https://github.com/apache/incubator-apisix/pull/340)
- 支持在 nginx.conf 中配置 real_ip 指令，以及增加函数来获取 ip. [#236](https://github.com/apache/incubator-apisix/pull/236)

### Dashboard

- :sunrise: **增加内置的 dashboard**. [#327](https://github.com/apache/incubator-apisix/pull/327)

### Test

- 在 Travis CI 中支持 OSX. [#217](https://github.com/apache/incubator-apisix/pull/217)
- 把所有依赖安装到 `deps` 目录。[#248](https://github.com/apache/incubator-apisix/pull/248)

[Back to TOC](#table-of-contents)
