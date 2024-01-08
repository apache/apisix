---
title: Changelog
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

- :sunrise: Support the use of lua-resty-events module for better performance: 
  - [#10550](https://github.com/apache/apisix/pull/10550)
  - [#10558](https://github.com/apache/apisix/pull/10558)
- :sunrise: Upgrade OpenSSL 1.1.1 to OpenSSL 3: [#10724](https://github.com/apache/apisix/pull/10724)

### Plugins

- :sunrise: Add jwe-decrypt plugin: [#10252](https://github.com/apache/apisix/pull/10252)
- :sunrise: Support brotli when use filters.regex option (response-rewrite): [#10733](https://github.com/apache/apisix/pull/10733)
- :sunrise: Add multi-auth plugin: [#10482](https://github.com/apache/apisix/pull/10482)
- :sunrise: Add `required scopes` configuration property to `openid-connect` plugin: [#10493](https://github.com/apache/apisix/pull/10493)
- :sunrise: Support for the Timing-Allow-Origin header (cors): [#9365](https://github.com/apache/apisix/pull/9365)
- :sunrise: Add brotli plugin: [#10515](https://github.com/apache/apisix/pull/10515)
- :sunrise: Body-transformer plugin enhancement(#10472): [#10496](https://github.com/apache/apisix/pull/10496)
- :sunrise: Set minLength of redis_cluster_nodes to 1 for limit-count plugin: [#10612](https://github.com/apache/apisix/pull/10612)
- :sunrise: Allow to use environment variables for limit-count plugin settings: [#10607](https://github.com/apache/apisix/pull/10607)

### Bugfixes

- Fix: When the upstream nodes are of array type, the port should be an optional field: [#10477](https://github.com/apache/apisix/pull/10477)
- Fix: Incorrect variable extraction in fault-injection plugin: [#10485](https://github.com/apache/apisix/pull/10485)
- Fix: All consumers should share the same counter (limit-count): [#10541](https://github.com/apache/apisix/pull/10541)
- Fix: Safely remove upstream when sending route to opa plugin: [#10552](https://github.com/apache/apisix/pull/10552)
- Fix: Missing etcd init_dir and unable to list resource: [#10569](https://github.com/apache/apisix/pull/10569)
- Fix: Forward-auth request body is too large: [#10589](https://github.com/apache/apisix/pull/10589)
- Fix: Memory leak caused by timer that never quit: [#10614](https://github.com/apache/apisix/pull/10614)
- Fix: Do not invoke add_header if value resolved as nil in proxy-rewrite plugin: [#10619](https://github.com/apache/apisix/pull/10619)
- Fix: Frequent traversal of all keys in etcd leads to high CPU usage: [#10671](https://github.com/apache/apisix/pull/10671)
- Fix: For prometheus upstream_status metrics, mostly_healthy is healthy: [#10639](https://github.com/apache/apisix/pull/10639)
- Fix: Avoid getting a nil value in log phase in zipkin: [#10666](https://github.com/apache/apisix/pull/10666)
- Fix: Enable openid-connect plugin without redirect_uri got 500 error: [#7690](https://github.com/apache/apisix/pull/7690)
- Fix: Add redirect_after_logout_uri for ODIC that do not have an end_session_endpoint: [#10653](https://github.com/apache/apisix/pull/10653)
- Fix: Response-rewrite filters.regex does not apply when content-encoding is gzip: [#10637](https://github.com/apache/apisix/pull/10637)
- Fix: The leak of prometheus metrics: [#10655](https://github.com/apache/apisix/pull/10655)
- Fix: Authz-keycloak add return detail err: [#10691](https://github.com/apache/apisix/pull/10691)
- Fix: upstream nodes was not updated correctly by service discover: [#10722](https://github.com/apache/apisix/pull/10722)
- Fix: apisix restart failed: [#10696](https://github.com/apache/apisix/pull/10696)

## 3.7.0

### Change

- :warning: Creating core resources does not allow passing in `create_time` and `update_time`: [#10232](https://github.com/apache/apisix/pull/10232)
- :warning: Remove self-contained info fields `exptime` and `validity_start` and `validity_end` from ssl schema: [10323](https://github.com/apache/apisix/pull/10323)
- :warning: Replace `route` with `apisix.route_name`, `service` with `apisix.service_name` in the attributes of opentelemetry plugin to follow the standards for span name and attributes: [#10393](https://github.com/apache/apisix/pull/10393)

### Core

- :sunrise: Added token to support access control for consul discovery: [#10278](https://github.com/apache/apisix/pull/10278)
- :sunrise: Support configuring `service_id` in stream_route to reference service resources: [#10298](https://github.com/apache/apisix/pull/10298)
- :sunrise: Using `apisix-runtime` as the apisix runtime:
  - [#10415](https://github.com/apache/apisix/pull/10415)
  - [#10427](https://github.com/apache/apisix/pull/10427)

### Plugins

- :sunrise: Add tests for authz-keycloak with apisix secrets: [#10353](https://github.com/apache/apisix/pull/10353)
- :sunrise: Add authorization params to openid-connect plugin: [#10058](https://github.com/apache/apisix/pull/10058)
- :sunrise: Support set variable in zipkin plugin: [#10361](https://github.com/apache/apisix/pull/10361)
- :sunrise: Support Nacos ak/sk authentication: [#10445](https://github.com/apache/apisix/pull/10445)

### Bugfixes

- Fix: Use warn log for get healthcheck target status failure:
  - [#10156](https://github.com/apache/apisix/pull/10156)
- Fix: Keep healthcheck target state when upstream changes:
  - [#10312](https://github.com/apache/apisix/pull/10312)
  - [#10307](https://github.com/apache/apisix/pull/10307)
- Fix: Add name field in plugin_config schema for consistency: [#10315](https://github.com/apache/apisix/pull/10315)
- Fix: Optimize tls in upstream_schema and wrong variable: [#10269](https://github.com/apache/apisix/pull/10269)
- Fix(consul): Failed to exit normally: [#10342](https://github.com/apache/apisix/pull/10342)
- Fix: The request header with `Content-Type: application/x-www-form-urlencoded;charset=utf-8` will cause vars condition `post_arg_xxx` matching to failed: [#10372](https://github.com/apache/apisix/pull/10372)
- Fix: Make install failed on mac: [#10403](https://github.com/apache/apisix/pull/10403)
- Fix(log-rotate): Log compression timeout caused data loss: [#8620](https://github.com/apache/apisix/pull/8620)
- Fix(kafka-logger): Remove 0 from enum of required_acks: [#10469](https://github.com/apache/apisix/pull/10469)

## 3.6.0

### Change

- :warning: Remove gRPC support between APISIX and etcd and remove `etcd.use_grpc` configuration option: [#10015](https://github.com/apache/apisix/pull/10015)
- :warning: Remove conf server. The data plane no longer supports direct communication with the control plane, and the configuration should be adjusted from `config_provider: control_plane` to `config_provider: etcd`: [#10012](https://github.com/apache/apisix/pull/10012)
- :warning: Enforce strict schema validation on the properties of the core APISIX resources: [#10233](https://github.com/apache/apisix/pull/10233)

### Core

- :sunrise: Support configuring the buffer size of the access log: [#10225](https://github.com/apache/apisix/pull/10225)
- :sunrise: Support the use of local DNS resolvers in service discovery by configuring `resolv_conf`: [#9770](https://github.com/apache/apisix/pull/9770)
- :sunrise: Remove Rust dependency for installation: [#10121](https://github.com/apache/apisix/pull/10121)
- :sunrise: Support Dubbo protocol in xRPC [#9660](https://github.com/apache/apisix/pull/9660)

### Plugins

- :sunrise: Support https in traffic-split plugin: [#9115](https://github.com/apache/apisix/pull/9115)
- :sunrise: Support rewrite request body in external plugin:[#9990](https://github.com/apache/apisix/pull/9990)
- :sunrise: Support set nginx variables in opentelemetry plugin: [#8871](https://github.com/apache/apisix/pull/8871)
- :sunrise: Support unix sock host pattern in the chaitin-waf plugin: [#10161](https://github.com/apache/apisix/pull/10161)

### Bugfixes

- Fix GraphQL POST request route matching exception: [#10198](https://github.com/apache/apisix/pull/10198)
- Fix error on array of multiline string in `apisix.yaml`: [#10193](https://github.com/apache/apisix/pull/10193)
- Add error handlers for invalid `cache_zone` configuration in the `proxy-cache` plugin: [#10138](https://github.com/apache/apisix/pull/10138)

## 3.5.0

### Change

- :warning: remove snowflake algorithm in the request-id plugin: [#9715](https://github.com/apache/apisix/pull/9715)
- :warning: No longer compatible with OpenResty 1.19, it needs to be upgraded to 1.21+: [#9913](https://github.com/apache/apisix/pull/9913)
- :warning: Remove the configuration item `apisix.stream_proxy.only`, the L4/L7 proxy needs to be enabled through the configuration item `apisix.proxy_mode`: [#9607](https://github.com/apache/apisix/pull/9607)
- :warning: The admin-api `/apisix/admin/plugins?all=true` marked as deprecated: [#9580](https://github.com/apache/apisix/pull/9580)
- :warning: allowlist and denylist can't be enabled at the same time in ua-restriction plugin: [#9841](https://github.com/apache/apisix/pull/9841)

### Core

- :sunrise: Support host level dynamic setting of tls protocol version: [#9903](https://github.com/apache/apisix/pull/9903)
- :sunrise: Support force delete resource: [#9810](https://github.com/apache/apisix/pull/9810)
- :sunrise: Support pulling env vars from yaml keys: [#9855](https://github.com/apache/apisix/pull/9855)
- :sunrise: Add schema validate API in admin-api: [#10065](https://github.com/apache/apisix/pull/10065)

### Plugins

- :sunrise: Add chaitin-waf plugin: [#9838](https://github.com/apache/apisix/pull/9838)
- :sunrise: Support vars for file-logger plugin: [#9712](https://github.com/apache/apisix/pull/9712)
- :sunrise: Support adding response headers for mock plugin: [#9720](https://github.com/apache/apisix/pull/9720)
- :sunrise: Support regex_uri with unsafe_uri for proxy-rewrite plugin: [#9813](https://github.com/apache/apisix/pull/9813)
- :sunrise: Support set client_email field for google-cloud-logging plugin: [#9813](https://github.com/apache/apisix/pull/9813)
- :sunrise: Support sending headers upstream returned by OPA server for opa plugin: [#9710](https://github.com/apache/apisix/pull/9710)
- :sunrise: Support configuring proxy server for openid-connect plugin: [#9948](https://github.com/apache/apisix/pull/9948)

### Bugfixes

- Fix(log-rotate): the max_kept configuration doesn't work when using custom name: [#9749](https://github.com/apache/apisix/pull/9749)
- Fix(limit_conn): do not use the http variable in stream mode: [#9816](https://github.com/apache/apisix/pull/9816)
- Fix(loki-logger): getting an error with log_labels: [#9850](https://github.com/apache/apisix/pull/9850)
- Fix(limit-count): X-RateLimit-Reset shouldn't be set to 0 after request be rejected: [#9978](https://github.com/apache/apisix/pull/9978)
- Fix(nacos): attempt to index upvalue 'applications' (a nil value): [#9960](https://github.com/apache/apisix/pull/9960)
- Fix(etcd): can't sync etcd data if key has special character: [#9967](https://github.com/apache/apisix/pull/9967)
- Fix(tencent-cloud-cls): dns parsing failure: [#9843](https://github.com/apache/apisix/pull/9843)
- Fix(reload): worker not exited when executing quit or reload command [#9909](https://github.com/apache/apisix/pull/9909)
- Fix(traffic-split): upstream_id validity verification [#10008](https://github.com/apache/apisix/pull/10008)

## 3.4.0

### Core

- :sunrise: Support route-level MTLS [#9322](https://github.com/apache/apisix/pull/9322)
- :sunrise: Support id schema for global_rules [#9517](https://github.com/apache/apisix/pull/9517)
- :sunrise: Support use a single long http connection to watch all resources for etcd [#9456](https://github.com/apache/apisix/pull/9456)
- :sunrise: Support max len 256 for ssl label [#9301](https://github.com/apache/apisix/pull/9301)

### Plugins

- :sunrise: Support multiple regex pattern matching for proxy_rewrite plugin [#9194](https://github.com/apache/apisix/pull/9194)
- :sunrise: Add loki-logger plugin [#9399](https://github.com/apache/apisix/pull/9399)
- :sunrise: Allow user configure DEFAULT_BUCKETS for prometheus plugin [#9673](https://github.com/apache/apisix/pull/9673)

### Bugfixes

- Fix(body-transformer): xml2lua: replace empty table with empty string [#9669](https://github.com/apache/apisix/pull/9669)
- Fix: opentelemetry and grpc-transcode plugins cannot work together [#9606](https://github.com/apache/apisix/pull/9606)
- Fix(skywalking-logger, error-log-logger): support $hostname in skywalking service_instance_name [#9401](https://github.com/apache/apisix/pull/9401)
- Fix(admin): fix secrets do not support to update attributes by PATCH [#9510](https://github.com/apache/apisix/pull/9510)
- Fix(http-logger): default request path should be '/' [#9472](https://github.com/apache/apisix/pull/9472)
- Fix: syslog plugin doesn't work [#9425](https://github.com/apache/apisix/pull/9425)
- Fix: wrong log format for splunk-hec-logging [#9478](https://github.com/apache/apisix/pull/9478)
- Fix(etcd): reuse cli and enable keepalive [#9420](https://github.com/apache/apisix/pull/9420)
- Fix: upstream key config add mqtt_client_id support [#9450](https://github.com/apache/apisix/pull/9450)
- Fix: body-transformer plugin return raw body anytime [#9446](https://github.com/apache/apisix/pull/9446)
- Fix(wolf-rbac): other plugin in consumer not effective when consumer used wolf-rbac plugin [#9298](https://github.com/apache/apisix/pull/9298)
- Fix: always parse domain when host is domain name [#9332](https://github.com/apache/apisix/pull/9332)
- Fix: response-rewrite plugin can't add only one character [#9372](https://github.com/apache/apisix/pull/9372)
- Fix(consul): support to fetch only health endpoint [#9204](https://github.com/apache/apisix/pull/9204)

## 3.3.0

**The changes marked with :warning: are not backward compatible.**

### Change

- :warning: Change the default router from `radixtree_uri` to `radixtree_host_uri`: [#9047](https://github.com/apache/apisix/pull/9047)
- :warning: CORS plugin will add `Vary: Origin` header when `allow_origin` is not `*`: [#9010](https://github.com/apache/apisix/pull/9010)

### Core

- :sunrise: Support store route's cert in secrets manager: [#9247](https://github.com/apache/apisix/pull/9247)
- :sunrise: Support bypassing Admin API Auth by configuration: [#9147](https://github.com/apache/apisix/pull/9147)

### Plugins

- :sunrise: Support header injection for `fault-injection` plugin: [#9039](https://github.com/apache/apisix/pull/9039)
- :sunrise: Support variable when rewrite header in `proxy-rewrite` plugin: [#9112](https://github.com/apache/apisix/pull/9112)
- :sunrise: `limit-count` plugin supports `username` and `ssl` for redis policy: [#9185](https://github.com/apache/apisix/pull/9185)

### Bugfixes

- Fix etcd data sync exception: [#8493](https://github.com/apache/apisix/pull/8493)
- Fix invalidate cache in `core.request.add_header` and fix some calls: [#8824](https://github.com/apache/apisix/pull/8824)
- Fix the high CPU and memory usage cause by healthcheck impl: [#9015](https://github.com/apache/apisix/pull/9015)
- Consider using `allow_origins_by_regex` only when it is not `nil`: [#9028](https://github.com/apache/apisix/pull/9028)
- Check upstream reference in `traffic-split` plugin when delete upstream: [#9044](https://github.com/apache/apisix/pull/9044)
- Fix failing to connect to etcd at startup: [#9077](https://github.com/apache/apisix/pull/9077)
- Fix health checker leak for domain nodes: [#9090](https://github.com/apache/apisix/pull/9090)
- Prevent non `127.0.0.0/24` to access admin api with empty admin_key: [#9146](https://github.com/apache/apisix/pull/9146)
- Ensure `hold_body_chunk` should use separate buffer for each plugin in case of pollution: [#9266](https://github.com/apache/apisix/pull/9266)
- Ensure `batch-requests` plugin read trailer headers if existed: [#9289](https://github.com/apache/apisix/pull/9289)
- Ensure `proxy-rewrite` should set `ngx.var.uri`: [#9309](https://github.com/apache/apisix/pull/9309)

## 3.2.1

**This is an LTS maintenance release and you can see the CHANGELOG in `release/3.2` branch.**

[https://github.com/apache/apisix/blob/release/3.2/CHANGELOG.md#321](https://github.com/apache/apisix/blob/release/3.2/CHANGELOG.md#321)

## 3.2.0

### Change

- Deprecated separate Vault configuration in jwt-auth. Users can use secret to achieve the same function: [#8660](https://github.com/apache/apisix/pull/8660)

### Core

- :sunrise: Support Vault token to configure secret through environment variables: [#8866](https://github.com/apache/apisix/pull/8866)
- :sunrise: Supports service discovery on stream subsystem:
     - [#8583](https://github.com/apache/apisix/pull/8583)
     - [#8593](https://github.com/apache/apisix/pull/8593)
     - [#8584](https://github.com/apache/apisix/pull/8584)
     - [#8640](https://github.com/apache/apisix/pull/8640)
     - [#8633](https://github.com/apache/apisix/pull/8633)
     - [#8696](https://github.com/apache/apisix/pull/8696)
     - [#8826](https://github.com/apache/apisix/pull/8826)

### Plugins

- :sunrise: Add RESTful to graphQL conversion plugin: [#8959](https://github.com/apache/apisix/pull/8959)
- :sunrise: Supports setting the log format on each log plugin:
     - [#8806](https://github.com/apache/apisix/pull/8806)
     - [#8643](https://github.com/apache/apisix/pull/8643)
- :sunrise: Add request body/response body conversion plugin: [#8766](https://github.com/apache/apisix/pull/8766)
- :sunrise: Support sending error logs to Kafka: [#8693](https://github.com/apache/apisix/pull/8693)
- :sunrise: limit-count plugin supports X-RateLimit-Reset: [#8578](https://github.com/apache/apisix/pull/8578)
- :sunrise: limit-count plugin supports setting TLS to access Redis cluster: [#8558](https://github.com/apache/apisix/pull/8558)
- :sunrise: consumer-restriction plugin supports permission control via consumer_group_id: [#8567](https://github.com/apache/apisix/pull/8567)

### Bugfixes

- Fix mTLS protection when the host and SNI mismatch: [#8967](https://github.com/apache/apisix/pull/8967)
- The proxy-rewrite plugin should escape URI parameter parts if they do not come from user config: [#8888](https://github.com/apache/apisix/pull/8888)
- Admin API PATCH operation should return 200 status code after success: [#8855](https://github.com/apache/apisix/pull/8855)
- Under certain conditions, the reload after etcd synchronization failure does not take effect: [#8736](https://github.com/apache/apisix/pull/8736)
- Fix the problem that the nodes found by the Consul service discovery are incomplete: [#8651](https://github.com/apache/apisix/pull/8651)
- Fix grpc-transcode plugin's conversion of Map data: [#8731](https://github.com/apache/apisix/pull/8731)
- External plugins should be able to set the content-type response header: [#8588](https://github.com/apache/apisix/pull/8588)
- When hotloading plugins, redundant timers may be left behind if the request-id plugin initializes the snowflake generator incorrectly: [#8556](https://github.com/apache/apisix/pull/8556)
- Close previous proto synchronizer for grpc-transcode when hotloading plugins: [#8557](https://github.com/apache/apisix/pull/8557)

## 3.1.0

### Core

- :sunrise: Support for etcd configuration synchronization via gRPC:
    - [#8485](https://github.com/apache/apisix/pull/8485)
    - [#8450](https://github.com/apache/apisix/pull/8450)
    - [#8411](https://github.com/apache/apisix/pull/8411)
- :sunrise: Support for configuring encrypted fields in plugins:
    - [#8487](https://github.com/apache/apisix/pull/8487)
    - [#8403](https://github.com/apache/apisix/pull/8403)
- :sunrise: Support for placing partial fields in Vault or environment variable using secret resources:
    - [#8448](https://github.com/apache/apisix/pull/8448)
    - [#8421](https://github.com/apache/apisix/pull/8421)
    - [#8412](https://github.com/apache/apisix/pull/8412)
    - [#8394](https://github.com/apache/apisix/pull/8394)
    - [#8390](https://github.com/apache/apisix/pull/8390)
- :sunrise: Allows upstream configuration in the stream subsystem as a domain name: [#8500](https://github.com/apache/apisix/pull/8500)
- :sunrise: Support Consul service discovery: [#8380](https://github.com/apache/apisix/pull/8380)

### Plugin

- :sunrise: Optimize resource usage for prometheus collection: [#8434](https://github.com/apache/apisix/pull/8434)
- :sunrise: Add inspect plugin for easy debugging: [#8400](https://github.com/apache/apisix/pull/8400)
- :sunrise: jwt-auth plugin supports parameters to hide authentication token from upstream : [#8206](https://github.com/apache/apisix/pull/8206)
- :sunrise: proxy-rewrite plugin supports adding new request headers without overwriting existing request headers with the same name: [#8336](https://github.com/apache/apisix/pull/8336)
- :sunrise: grpc-transcode plugin supports setting the grpc-status-details-bin response header into the response body: [#7639](https://github.com/apache/apisix/pull/7639)
- :sunrise: proxy-mirror plugin supports setting the prefix: [#8261](https://github.com/apache/apisix/pull/8261)

### Bugfix

- Fix the problem that the plug-in configured under service object cannot take effect in time under some circumstances: [#8482](https://github.com/apache/apisix/pull/8482)
- Fix an occasional 502 problem when http and grpc share the same upstream connection due to connection pool reuse: [#8364](https://github.com/apache/apisix/pull/8364)
- file-logger should avoid buffer-induced log truncation when writing logs: [#7884](https://github.com/apache/apisix/pull/7884)
- max_kept parameter of log-rotate plugin should take effect on compressed files: [#8366](https://github.com/apache/apisix/pull/8366)
- Fix userinfo not being set when use_jwks is true in the openid-connect plugin: [#8347](https://github.com/apache/apisix/pull/8347)
- Fix an issue where x-forwarded-host cannot be changed in the proxy-rewrite plugin: [#8200](https://github.com/apache/apisix/pull/8200)
- Fix a bug where disabling the v3 admin API resulted in missing response bodies under certain circumstances: [#8349](https://github.com/apache/apisix/pull/8349)
- In zipkin plugin, pass trace ID even if there is a rejected sampling decision: [#8099](https://github.com/apache/apisix/pull/8099)
- Fix `_meta.filter` in plugin configuration not working with variables assigned after upstream response and custom variables in APISIX.
    - [#8162](https://github.com/apache/apisix/pull/8162)
    - [#8256](https://github.com/apache/apisix/pull/8256)

## 3.0.0

### Change

- `enable_cpu_affinity` is disabled by default to avoid this configuration affecting the behavior of APSISIX deployed in the container: [#8074](https://github.com/apache/apisix/pull/8074)

### Core

- :sunrise: Added Consumer Group entity to manage multiple consumers: [#7980](https://github.com/apache/apisix/pull/7980)
- :sunrise: Supports configuring the order in which DNS resolves domain name types: [#7935](https://github.com/apache/apisix/pull/7935)
- :sunrise: Support configuring multiple `key_encrypt_salt` for rotation: [#7925](https://github.com/apache/apisix/pull/7925)

### Plugin

- :sunrise: Added ai plugin to dynamically optimize the execution path of APISIX according to the scene:
    - [#8102](https://github.com/apache/apisix/pull/8102)
    - [#8113](https://github.com/apache/apisix/pull/8113)
    - [#8120](https://github.com/apache/apisix/pull/8120)
    - [#8128](https://github.com/apache/apisix/pull/8128)
    - [#8130](https://github.com/apache/apisix/pull/8130)
    - [#8149](https://github.com/apache/apisix/pull/8149)
    - [#8157](https://github.com/apache/apisix/pull/8157)
- :sunrise: Support `session_secret` in openid-connect plugin to resolve the inconsistency of `session_secret` among multiple workers: [#8068](https://github.com/apache/apisix/pull/8068)
- :sunrise: Support sasl config in kafka-logger plugin: [#8050](https://github.com/apache/apisix/pull/8050)
- :sunrise: Support set resolve domain in proxy-mirror plugin: [#7861](https://github.com/apache/apisix/pull/7861)
- :sunrise: Support `brokers` property in kafka-logger plugin, which supports different broker to set the same host: [#7999](https://github.com/apache/apisix/pull/7999)
- :sunrise: Support get response body in ext-plugin-post-resp: [#7947](https://github.com/apache/apisix/pull/7947)
- :sunrise: Added cas-auth plugin to support CAS authentication: [#7932](https://github.com/apache/apisix/pull/7932)

### Bugfix

- Conditional expressions of workflow plugin should support operators: [#8121](https://github.com/apache/apisix/pull/8121)
- Fix loading problem of batch processor plugin when prometheus plugin is disabled: [#8079](https://github.com/apache/apisix/pull/8079)
- When APISIX starts, delete the old conf server sock file if it exists: [#8022](https://github.com/apache/apisix/pull/8022)
- Disable core.grpc when gRPC-client-nginx-module module is not compiled: [#8007](https://github.com/apache/apisix/pull/8007)

## 3.0.0-beta

Here we use 2.99.0 as the version number in the source code instead of the code name
`3.0.0-beta` for two reasons:

1. avoid unexpected errors when some programs try to compare the
version, as `3.0.0-beta` contains `3.0.0` and is longer than it.
2. some package system might not allow package which has a suffix
after the version number.

### Change

#### Moves the config_center, etcd and Admin API configuration to the deployment

We've adjusted the configuration in the static configuration file, so you need to update the configuration in `config.yaml` as well:

- The `config_center` function is now implemented by `config_provider` under `deployment`: [#7901](https://github.com/apache/apisix/pull/7901)
- The `etcd` field is moved to `deployment`: [#7860](https://github.com/apache/apisix/pull/7860)
- The following Admin API configuration is moved to the `admin` field under `deployment`: [#7823](https://github.com/apache/apisix/pull/7823)
    - admin_key
    - enable_admin_cors
    - allow_admin
    - admin_listen
    - https_admin
    - admin_api_mtls
    - admin_api_version

You can refer to the latest `config-default.yaml` for details.

#### Removing multiple deprecated configurations

With the new 3.0 release, we took the opportunity to clean out many configurations that were previously marked as deprecated.

In the static configuration, we removed several fields as follows:

- Removed `enable_http2` and `listen_port` from `apisix.ssl`: [#7717](https://github.com/apache/apisix/pull/7717)
- Removed `apisix.port_admin`: [#7716](https://github.com/apache/apisix/pull/7716)
- Removed `etcd.health_check_retry`: [#7676](https://github.com/apache/apisix/pull/7676)
- Removed `nginx_config.http.lua_shared_dicts`: [#7677](https://github.com/apache/apisix/pull/7677)
- Removed `apisix.real_ip_header`: [#7696](https://github.com/apache/apisix/pull/7696)

In the dynamic configuration, we made the following adjustments:

- Moved `disable` of the plugin configuration under `_meta`: [#7707](https://github.com/apache/apisix/pull/7707)
- Removed `service_protocol` from the Route: [#7701](https://github.com/apache/apisix/pull/7701)

There are also specific plugin level changes:

- Removed `audience` field from authz-keycloak: [#7683](https://github.com/apache/apisix/pull/7683)
- Removed `upstream` field from mqtt-proxy: [#7694](https://github.com/apache/apisix/pull/7694)
- tcp-related configuration placed under the `tcp` field in error-log-logger: [#7700](https://github.com/apache/apisix/pull/7700)
- Removed `max_retry_times` and `retry_interval` fields from syslog: [#7699](https://github.com/apache/apisix/pull/7699)
- The `scheme` field has been removed from proxy-rewrite: [#7695](https://github.com/apache/apisix/pull/7695)

#### New Admin API response format

We have adjusted the response format of the Admin API in several PRs as follows:

- [#7630](https://github.com/apache/apisix/pull/7630)
- [#7622](https://github.com/apache/apisix/pull/7622)

The new response format is shown below:

Returns a single configuration:

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

Returns multiple configurations:

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

#### Other

- Port of Admin API changed to 9180: [#7806](https://github.com/apache/apisix/pull/7806)
- We only support OpenResty 1.19.3.2 and above: [#7625](https://github.com/apache/apisix/pull/7625)
- Adjusted the priority of the Plugin Config object so that the priority of a plugin configuration with the same name changes from Consumer > Plugin Config > Route > Service to Consumer > Route > Plugin Config > Service: [#7614](https://github.com/apache/apisix/pull/7614)

### Core

- Integrating grpc-client-nginx-module to APISIX: [#7917](https://github.com/apache/apisix/pull/7917)
- k8s service discovery support for configuring multiple clusters: [#7895](https://github.com/apache/apisix/pull/7895)

### Plugin

- Support for injecting header with specified prefix in opentelemetry plugin: [#7822](https://github.com/apache/apisix/pull/7822)
- Added openfunction plugin: [#7634](https://github.com/apache/apisix/pull/7634)
- Added elasticsearch-logger plugin: [#7643](https://github.com/apache/apisix/pull/7643)
- response-rewrite plugin supports adding response bodies: [#7794](https://github.com/apache/apisix/pull/7794)
- log-rorate supports specifying the maximum size to cut logs: [#7749](https://github.com/apache/apisix/pull/7749)
- Added workflow plug-in.
    - [#7760](https://github.com/apache/apisix/pull/7760)
    - [#7771](https://github.com/apache/apisix/pull/7771)
- Added Tencent Cloud Log Service plugin: [#7593](https://github.com/apache/apisix/pull/7593)
- jwt-auth supports ES256 algorithm: [#7627](https://github.com/apache/apisix/pull/7627)
- ldap-auth internal implementation, switching from lualdap to lua-resty-ldap: [#7590](https://github.com/apache/apisix/pull/7590)
- http request metrics within the prometheus plugin supports setting additional labels via variables: [#7549](https://github.com/apache/apisix/pull/7549)
- The clickhouse-logger plugin supports specifying multiple clickhouse endpoints: [#7517](https://github.com/apache/apisix/pull/7517)

### Bugfix

- gRPC proxy sets :authority request header to configured upstream Host: [#7939](https://github.com/apache/apisix/pull/7939)
- response-rewrite writing to an empty body may cause AIPSIX to fail to respond to the request: [#7836](https://github.com/apache/apisix/pull/7836)
- Fix the problem that when using Plugin Config and Consumer at the same time, there is a certain probability that the plugin configuration is not updated: [#7965](https://github.com/apache/apisix/pull/7965)
- Only reopen log files once when log cutting: [#7869](https://github.com/apache/apisix/pull/7869)
- Passive health checks should not be enabled by default: [#7850](https://github.com/apache/apisix/pull/7850)
- The zipkin plugin should pass trace IDs upstream even if it does not sample: [#7833](https://github.com/apache/apisix/pull/7833)
- Correction of opentelemetry span kind to server: [#7830](https://github.com/apache/apisix/pull/7830)
- in limit-count plugin, different routes with the same configuration should not share the same counter: [#7750](https://github.com/apache/apisix/pull/7750)
- Fix occasional exceptions thrown when removing clean_handler: [#7648](https://github.com/apache/apisix/pull/7648)
- Allow direct use of IPv6 literals when configuring upstream nodes: [#7594](https://github.com/apache/apisix/pull/7594)
- The wolf-rbac plugin adjusts the way it responds to errors:
    - [#7561](https://github.com/apache/apisix/pull/7561)
    - [#7497](https://github.com/apache/apisix/pull/7497)
- the phases after proxy didn't run when 500 error happens before proxy: [#7703](https://github.com/apache/apisix/pull/7703)
- avoid error when multiple plugins associated with consumer and have rewrite phase: [#7531](https://github.com/apache/apisix/pull/7531)
- upgrade lua-resty-etcd to 1.8.3 which fixes various issues: [#7565](https://github.com/apache/apisix/pull/7565)

## 2.15.3

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.15` branch.**

[https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2153](https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2153)

## 2.15.2

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.15` branch.**

[https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2152](https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2152)

## 2.15.1

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.15` branch.**

[https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2151](https://github.com/apache/apisix/blob/release/2.15/CHANGELOG.md#2151)

## 2.15.0

### Change

- We now map the grpc error code OUT_OF_RANGE to http code 400 in grpc-transcode plugin: [#7419](https://github.com/apache/apisix/pull/7419)
- Rename health_check_retry configuration in etcd section of `config-default.yaml` to startup_retry: [#7304](https://github.com/apache/apisix/pull/7304)
- Remove `upstream.enable_websocket` which is deprecated since 2020: [#7222](https://github.com/apache/apisix/pull/7222)

### Core

- Support running plugins conditionally: [#7453](https://github.com/apache/apisix/pull/7453)
- Allow users to specify plugin execution priority: [#7273](https://github.com/apache/apisix/pull/7273)
- Support getting upstream certificate from ssl object: [#7221](https://github.com/apache/apisix/pull/7221)
- Allow customizing error response in the plugin: [#7128](https://github.com/apache/apisix/pull/7128)
- Add metrics to xRPC Redis proxy: [#7183](https://github.com/apache/apisix/pull/7183)
- Introduce deployment role to simplify the deployment of APISIX:
    - [#7405](https://github.com/apache/apisix/pull/7405)
    - [#7417](https://github.com/apache/apisix/pull/7417)
    - [#7392](https://github.com/apache/apisix/pull/7392)
    - [#7365](https://github.com/apache/apisix/pull/7365)
    - [#7249](https://github.com/apache/apisix/pull/7249)

### Plugin

- Add ngx.shared.dict statistic in promethues plugin: [#7412](https://github.com/apache/apisix/pull/7412)
- Allow using unescaped raw URL in proxy-rewrite plugin: [#7401](https://github.com/apache/apisix/pull/7401)
- Add PKCE support to the openid-connect plugin: [#7370](https://github.com/apache/apisix/pull/7370)
- Support custom log format in sls-logger plugin: [#7328](https://github.com/apache/apisix/pull/7328)
- Export some params for kafka-client in kafka-logger plugin: [#7266](https://github.com/apache/apisix/pull/7266)
- Add support for capturing OIDC refresh tokens in openid-connect plugin: [#7220](https://github.com/apache/apisix/pull/7220)
- Add prometheus plugin in stream subsystem: [#7174](https://github.com/apache/apisix/pull/7174)

### Bugfix

- clear remain state from the latest try before retrying in Kubernetes discovery: [#7506](https://github.com/apache/apisix/pull/7506)
- the query string was repeated twice when enabling both http_to_https and append_query_string in the redirect plugin: [#7433](https://github.com/apache/apisix/pull/7433)
- don't send empty Authorization header by default in http-logger: [#7444](https://github.com/apache/apisix/pull/7444)
- ensure both `group` and `disable` configurations can be used in limit-count: [#7384](https://github.com/apache/apisix/pull/7384)
- adjust the execution priority of request-id so the tracing plugins can use the request id: [#7281](https://github.com/apache/apisix/pull/7281)
- correct the transcode of repeated Message in grpc-transcode: [#7231](https://github.com/apache/apisix/pull/7231)
- var missing in proxy-cache cache key should be ignored: [#7168](https://github.com/apache/apisix/pull/7168)
- reduce memory usage when abnormal weights are given in chash: [#7103](https://github.com/apache/apisix/pull/7103)
- cache should be bypassed when the method mismatch in proxy-cache: [#7111](https://github.com/apache/apisix/pull/7111)
- Upstream keepalive should consider TLS param:
    - [#7054](https://github.com/apache/apisix/pull/7054)
    - [#7466](https://github.com/apache/apisix/pull/7466)
- The redirect plugin sets a correct port during redirecting HTTP to HTTPS:
    - [#7065](https://github.com/apache/apisix/pull/7065)

## 2.14.1

### Bugfix

- The "unix:" in the `real_ip_from` configuration should not break the batch-requests plugin: [#7106](https://github.com/apache/apisix/pull/7106)

## 2.14.0

### Change

- To adapt the change of OpenTelemetry spec, the default port of OTLP/HTTP is changed to 4318: [#7007](https://github.com/apache/apisix/pull/7007)

### Core

- Introduce an experimental feature to allow subscribing Kafka message via APISIX. This feature is based on the pubsub framework running above websocket:
    - [#7028](https://github.com/apache/apisix/pull/7028)
    - [#7032](https://github.com/apache/apisix/pull/7032)
- Introduce an experimental framework called xRPC to manage non-HTTP L7 traffic:
    - [#6885](https://github.com/apache/apisix/pull/6885)
    - [#6901](https://github.com/apache/apisix/pull/6901)
    - [#6919](https://github.com/apache/apisix/pull/6919)
    - [#6960](https://github.com/apache/apisix/pull/6960)
    - [#6965](https://github.com/apache/apisix/pull/6965)
    - [#7040](https://github.com/apache/apisix/pull/7040)
- Now we support adding delay according to the command & key during proxying Redis traffic, which is built above xRPC:
    - [#6999](https://github.com/apache/apisix/pull/6999)
- Introduce an experimental support to configure APISIX via xDS:
    - [#6614](https://github.com/apache/apisix/pull/6614)
    - [#6759](https://github.com/apache/apisix/pull/6759)
- Add `normalize_uri_like_servlet` option to normalize uri like servlet: [#6984](https://github.com/apache/apisix/pull/6984)
- Zookeeper service discovery via apisix-seed: [#6751](https://github.com/apache/apisix/pull/6751)

### Plugin

- The real-ip plugin supports recursive IP search like `real_ip_recursive`: [#6988](https://github.com/apache/apisix/pull/6988)
- The api-breaker plugin allows configuring response: [#6949](https://github.com/apache/apisix/pull/6949)
- The response-rewrite plugin supports body filters: [#6750](https://github.com/apache/apisix/pull/6750)
- The request-id plugin adds nanoid algorithm to generate ID: [#6779](https://github.com/apache/apisix/pull/6779)
- The file-logger plugin can cache & reopen file handler: [#6721](https://github.com/apache/apisix/pull/6721)
- Add casdoor plugin: [#6382](https://github.com/apache/apisix/pull/6382)
- The authz-keycloak plugin supports password grant: [#6586](https://github.com/apache/apisix/pull/6586)

### Bugfix

- Upstream keepalive should consider TLS param: [#7054](https://github.com/apache/apisix/pull/7054)
- Do not expose internal error message to the client:
    - [#6982](https://github.com/apache/apisix/pull/6982)
    - [#6859](https://github.com/apache/apisix/pull/6859)
    - [#6854](https://github.com/apache/apisix/pull/6854)
    - [#6853](https://github.com/apache/apisix/pull/6853)
    - [#6846](https://github.com/apache/apisix/pull/6846)
- DNS supports SRV record with port 0: [#6739](https://github.com/apache/apisix/pull/6739)
- client mTLS was ignored sometimes in TLS session reuse: [#6906](https://github.com/apache/apisix/pull/6906)
- The grpc-web plugin doesn't override Access-Control-Allow-Origin header in response: [#6842](https://github.com/apache/apisix/pull/6842)
- The syslog plugin's default timeout is corrected: [#6807](https://github.com/apache/apisix/pull/6807)
- The authz-keycloak plugin's `access_denied_redirect_uri` was bypassed sometimes: [#6794](https://github.com/apache/apisix/pull/6794)
- Handle `USR2` signal properly: [#6758](https://github.com/apache/apisix/pull/6758)
- The redirect plugin set a correct port during redirecting HTTP to HTTPS:
    - [#7065](https://github.com/apache/apisix/pull/7065)
    - [#6686](https://github.com/apache/apisix/pull/6686)
- Admin API rejects unknown stream plugin: [#6813](https://github.com/apache/apisix/pull/6813)

## 2.13.3

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.13` branch.**

[https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2133](https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2133)

## 2.13.2

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.13` branch.**

[https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2132](https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2132)

## 2.13.1

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.13` branch.**

[https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2131](https://github.com/apache/apisix/blob/release/2.13/CHANGELOG.md#2131)

## 2.13.0

### Change

- change(syslog): correct the configuration [#6551](https://github.com/apache/apisix/pull/6551)
- change(server-info): use a new approach(keepalive) to report DP info [#6202](https://github.com/apache/apisix/pull/6202)
- change(admin): empty nodes should be encoded as array [#6384](https://github.com/apache/apisix/pull/6384)
- change(prometheus): replace wrong apisix_nginx_http_current_connections{state="total"} label [#6327](https://github.com/apache/apisix/pull/6327)
- change: don't expose public API by default & remove plugin interceptor [#6196](https://github.com/apache/apisix/pull/6196)

### Core

- :sunrise: feat: add delayed_body_filter phase [#6605](https://github.com/apache/apisix/pull/6605)
- :sunrise: feat: support for reading environment variables from yaml configuration files [#6505](https://github.com/apache/apisix/pull/6505)
- :sunrise: feat: rerun rewrite phase for newly added plugins in consumer [#6502](https://github.com/apache/apisix/pull/6502)
- :sunrise: feat: add config to control write all status to x-upsream-apisix-status [#6392](https://github.com/apache/apisix/pull/6392)
- :sunrise: feat: add kubernetes discovery module [#4880](https://github.com/apache/apisix/pull/4880)
- :sunrise: feat(graphql): support http get and post json request [#6343](https://github.com/apache/apisix/pull/6343)

### Plugin

- :sunrise: feat: jwt-auth support custom parameters [#6561](https://github.com/apache/apisix/pull/6561)
- :sunrise: feat: set cors allow origins by plugin metadata [#6546](https://github.com/apache/apisix/pull/6546)
- :sunrise: feat: support post_logout_redirect_uri config in openid-connect plugin [#6455](https://github.com/apache/apisix/pull/6455)
- :sunrise: feat: mocking plugin [#5940](https://github.com/apache/apisix/pull/5940)
- :sunrise: feat(error-log-logger): add clickhouse for error-log-logger [#6256](https://github.com/apache/apisix/pull/6256)
- :sunrise: feat: clickhouse logger [#6215](https://github.com/apache/apisix/pull/6215)
- :sunrise: feat(grpc-transcode): support .pb file [#6264](https://github.com/apache/apisix/pull/6264)
- :sunrise: feat: development of Loggly logging plugin [#6113](https://github.com/apache/apisix/pull/6113)
- :sunrise: feat: add opentelemetry plugin [#6119](https://github.com/apache/apisix/pull/6119)
- :sunrise: feat: add public api plugin [#6145](https://github.com/apache/apisix/pull/6145)
- :sunrise: feat: add CSRF plugin [#5727](https://github.com/apache/apisix/pull/5727)

### Bugfix

- fix(skywalking,opentelemetry): trace request rejected by auth [#6617](https://github.com/apache/apisix/pull/6617)
- fix(log-rotate): should rotate logs strictly hourly(or minutely) [#6521](https://github.com/apache/apisix/pull/6521)
- fix: deepcopy doesn't copy the metatable [#6623](https://github.com/apache/apisix/pull/6623)
- fix(request-validate): handle duplicate key in JSON [#6625](https://github.com/apache/apisix/pull/6625)
- fix(prometheus): conflict between global rule and route configure [#6579](https://github.com/apache/apisix/pull/6579)
- fix(proxy-rewrite): when conf.headers are missing,conf.method can make effect [#6300](https://github.com/apache/apisix/pull/6300)
- fix(traffic-split): failed to match rule when the first rule failed [#6292](https://github.com/apache/apisix/pull/6292)
- fix(config_etcd): skip resync_delay while etcd watch timeout [#6259](https://github.com/apache/apisix/pull/6259)
- fix(proto): avoid sharing state [#6199](https://github.com/apache/apisix/pull/6199)
- fix(limit-count): keep the counter if the plugin conf is the same [#6151](https://github.com/apache/apisix/pull/6151)
- fix(admin): correct the count field of plugin-metadata/global-rule [#6155](https://github.com/apache/apisix/pull/6155)
- fix: add missing labels after merging route and service [#6177](https://github.com/apache/apisix/pull/6177)

## 2.12.1

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.12` branch.**

[https://github.com/apache/apisix/blob/release/2.12/CHANGELOG.md#2121](https://github.com/apache/apisix/blob/release/2.12/CHANGELOG.md#2121)

## 2.12.0

### Change

- change(serverless): rename "balancer" phase to "before_proxy" [#5992](https://github.com/apache/apisix/pull/5992)
- change: don't promise to support Tengine [#5961](https://github.com/apache/apisix/pull/5961)
- change: enable HTTP when stream proxy is set and enable_admin is true [#5867](https://github.com/apache/apisix/pull/5867)

### Core

- :sunrise: feat(L4): support TLS over TCP upstream [#6030](https://github.com/apache/apisix/pull/6030)
- :sunrise: feat: support registering custom variable [#5941](https://github.com/apache/apisix/pull/5941)
- :sunrise: feat(vault): vault lua module, integration with jwt-auth authentication plugin [#5745](https://github.com/apache/apisix/pull/5745)
- :sunrise: feat: enable L4 stream logging [#5768](https://github.com/apache/apisix/pull/5768)
- :sunrise: feat: add http_server_location_configuration_snippet configuration [#5740](https://github.com/apache/apisix/pull/5740)
- :sunrise: feat: support resolve default value when environment not set [#5675](https://github.com/apache/apisix/pull/5675)
- :sunrise: feat(wasm): run in http header_filter [#5544](https://github.com/apache/apisix/pull/5544)

### Plugin

- :sunrise: feat: support hide the authentication header in basic-auth with  a config [#6039](https://github.com/apache/apisix/pull/6039)
- :sunrise: feat: set proxy_request_buffering dynamically [#6075](https://github.com/apache/apisix/pull/6075)
- :sunrise: feat(mqtt): balance by client id [#6079](https://github.com/apache/apisix/pull/6079)
- :sunrise: feat: add forward-auth plugin [#6037](https://github.com/apache/apisix/pull/6037)
- :sunrise: feat(grpc-web): support gRPC-Web Proxy [#5964](https://github.com/apache/apisix/pull/5964)
- :sunrise: feat(limit-count): add constant key type [#5984](https://github.com/apache/apisix/pull/5984)
- :sunrise: feat(limit-count): allow sharing counter [#5881](https://github.com/apache/apisix/pull/5881)
- :sunrise: feat(splunk): support splunk hec logging plugin [#5819](https://github.com/apache/apisix/pull/5819)
- :sunrise: feat: basic support OPA plugin [#5734](https://github.com/apache/apisix/pull/5734)
- :sunrise: feat: rocketmq logger [#5653](https://github.com/apache/apisix/pull/5653)
- :sunrise: feat(mqtt-proxy): support using route's upstream [#5666](https://github.com/apache/apisix/pull/5666)
- :sunrise: feat(ext-plugin): support to get request body [#5600](https://github.com/apache/apisix/pull/5600)
- :sunrise: feat(plugins): aws lambda serverless [#5594](https://github.com/apache/apisix/pull/5594)
- :sunrise: feat(http/kafka-logger): support to log response body [#5550](https://github.com/apache/apisix/pull/5550)
- :sunrise: feat: Apache OpenWhisk plugin [#5518](https://github.com/apache/apisix/pull/5518)
- :sunrise: feat(plugin): support google cloud logging service [#5538](https://github.com/apache/apisix/pull/5538)

### Bugfix

- fix: the prometheus labels are inconsistent when error-log-logger is enabled [#6055](https://github.com/apache/apisix/pull/6055)
- fix(ipv6): allow disabling IPv6 resolve [#6023](https://github.com/apache/apisix/pull/6023)
- fix(mqtt): handle properties for MQTT 5 [#5916](https://github.com/apache/apisix/pull/5916)
- fix(sls-logger): unable to get millisecond part of the timestamp [#5820](https://github.com/apache/apisix/pull/5820)
- fix(mqtt-proxy): client id can be empty [#5816](https://github.com/apache/apisix/pull/5816)
- fix(ext-plugin): don't use stale key [#5782](https://github.com/apache/apisix/pull/5782)
- fix(log-rotate): race between reopen log & compression [#5715](https://github.com/apache/apisix/pull/5715)
- fix(batch-processor): we didn't free stale object actually [#5700](https://github.com/apache/apisix/pull/5700)
- fix: data pollution after passive health check is changed [#5589](https://github.com/apache/apisix/pull/5589)

## 2.11.0

### Change

- change(wolf-rbac): change default port number and add `authType` parameter to documentation [#5477](https://github.com/apache/apisix/pull/5477)

### Core

- :sunrise: feat: support advanced matching based on post form [#5409](https://github.com/apache/apisix/pull/5409)
- :sunrise: feat: initial wasm support [#5288](https://github.com/apache/apisix/pull/5288)
- :sunrise: feat(control): expose services[#5271](https://github.com/apache/apisix/pull/5271)
- :sunrise: feat(control): add dump upstream api [#5259](https://github.com/apache/apisix/pull/5259)
- :sunrise: feat: etcd cluster single node failure APISIX startup failure [#5158](https://github.com/apache/apisix/pull/5158)
- :sunrise: feat: support specify custom sni in etcd conf [#5206](https://github.com/apache/apisix/pull/5206)

### Plugin

- :sunrise: feat(plugin): azure serverless functions [#5479](https://github.com/apache/apisix/pull/5479)
- :sunrise: feat(kafka-logger): supports logging request body [#5501](https://github.com/apache/apisix/pull/5501)
- :sunrise: feat: provide skywalking logger plugin [#5478](https://github.com/apache/apisix/pull/5478)
- :sunrise: feat(plugins): Datadog for metrics collection [#5372](https://github.com/apache/apisix/pull/5372)
- :sunrise: feat(limit-* plugin):  fallback to remote_addr when key is missing [#5422](https://github.com/apache/apisix/pull/5422)
- :sunrise: feat(limit-count): support multiple variables as key [#5378](https://github.com/apache/apisix/pull/5378)
- :sunrise: feat(limit-conn): support multiple variables as key [#5354](https://github.com/apache/apisix/pull/5354)
- :sunrise: feat(proxy-rewrite): rewrite method [#5292](https://github.com/apache/apisix/pull/5292)
- :sunrise: feat(limit-req): support multiple variables as key [#5302](https://github.com/apache/apisix/pull/5302)
- :sunrise: feat(proxy-cache): support memory-based strategy [#5028](https://github.com/apache/apisix/pull/5028)
- :sunrise: feat(ext-plugin): avoid sending conf request more times [#5183](https://github.com/apache/apisix/pull/5183)
- :sunrise: feat: Add ldap-auth plugin [#3894](https://github.com/apache/apisix/pull/3894)

## 2.10.5

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.10` branch.**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2105](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2105)

## 2.10.4

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.10` branch.**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2104](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2104)

## 2.10.3

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.10` branch.**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2103](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2103)

## 2.10.2

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.10` branch.**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2102](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2102)

## 2.10.1

**This is an LTS maintenance release and you can see the CHANGELOG in `release/2.10` branch.**

[https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2101](https://github.com/apache/apisix/blob/release/2.10/CHANGELOG.md#2101)

## 2.10.0

### Change

- change(debug): move 'enable_debug' form config.yaml to debug.yaml [#5046](https://github.com/apache/apisix/pull/5046)
- change: use a new name to customize lua_shared_dict in nginx.conf [#5030](https://github.com/apache/apisix/pull/5030)
- change: drop the support of shell script installation [#4985](https://github.com/apache/apisix/pull/4985)

### Core

- :sunrise: feat(debug-mode): add dynamic debug mode [#5012](https://github.com/apache/apisix/pull/5012)
- :sunrise: feat: allow injecting logic to APISIX's method [#5068](https://github.com/apache/apisix/pull/5068)
- :sunrise: feat: allow configuring fallback SNI [#5000](https://github.com/apache/apisix/pull/5000)
- :sunrise: feat(stream_route): support CIDR in ip match [#4980](https://github.com/apache/apisix/pull/4980)
- :sunrise: feat: allow route to inherit hosts from service [#4977](https://github.com/apache/apisix/pull/4977)
- :sunrise: feat: support configurating the node listening address[#4856](https://github.com/apache/apisix/pull/4856)

### Plugin

- :sunrise: feat(hmac-auth): Add validate request body for hmac auth plugin [#5038](https://github.com/apache/apisix/pull/5038)
- :sunrise: feat(proxy-mirror): support mirror requests sample_ratio [#4965](https://github.com/apache/apisix/pull/4965)
- :sunrise: feat(referer-restriction): add blacklist and message [#4916](https://github.com/apache/apisix/pull/4916)
- :sunrise: feat(kafka-logger): add cluster name support [#4876](https://github.com/apache/apisix/pull/4876)
- :sunrise: feat(kafka-logger): add required_acks option [#4878](https://github.com/apache/apisix/pull/4878)
- :sunrise: feat(uri-blocker): add case insensitive switch [#4868](https://github.com/apache/apisix/pull/4868)

### Bugfix

- fix(radixtree_host_uri): correct matched host [#5124](https://github.com/apache/apisix/pull/5124)
- fix(radixtree_host_uri): correct matched path [#5104](https://github.com/apache/apisix/pull/5104)
- fix(nacos): distinguish services that has same name but in different groups or namespaces [#5083](https://github.com/apache/apisix/pull/5083)
- fix(nacos): continue to process other services when request failed [#5112](https://github.com/apache/apisix/pull/5112)
- fix(ssl): match sni in case-insensitive way [#5074](https://github.com/apache/apisix/pull/5074)
- fix(upstream): should not override default keepalive value [#5054](https://github.com/apache/apisix/pull/5054)
- fix(DNS): prefer SRV in service discovery [#4992](https://github.com/apache/apisix/pull/4992)
- fix(consul): retry connecting after a delay [#4979](https://github.com/apache/apisix/pull/4979)
- fix: avoid copying unwanted data when the domain's IP changed [#4952](https://github.com/apache/apisix/pull/4952)
- fix(plugin_config): recover plugin when plugin_config changed [#4888](https://github.com/apache/apisix/pull/4888)

## 2.9.0

### Change

- change: rename plugin's balancer method to before_proxy [#4697](https://github.com/apache/apisix/pull/4697)

### Core

- :sunrise: feat: increase timers limitation [#4843](https://github.com/apache/apisix/pull/4843)
- :sunrise: feat: make A/B test APISIX easier by removing "additionalProperties = false" [#4797](https://github.com/apache/apisix/pull/4797)
- :sunrise: feat: support dash in args (#4519) [#4676](https://github.com/apache/apisix/pull/4676)
- :sunrise: feat(admin): reject invalid proto [#4750](https://github.com/apache/apisix/pull/4750)

### Plugin

- :sunrise: feat(ext-plugin): support ExtraInfo [#4835](https://github.com/apache/apisix/pull/4835)
- :sunrise: feat(gzip): support special * to match any type [#4817](https://github.com/apache/apisix/pull/4817)
- :sunrise: feat(real-ip): implement the first version [#4813](https://github.com/apache/apisix/pull/4813)
- :sunrise: feat(limit-*): add custom reject-message for traffic control [#4808](https://github.com/apache/apisix/pull/4808)
- :sunrise: feat: Request-ID plugin add snowflake algorithm [#4559](https://github.com/apache/apisix/pull/4559)
- :sunrise: feat: Added authz-casbin plugin and doc and tests for it [#4710](https://github.com/apache/apisix/pull/4710)
- :sunrise: feat: add error log skywalking reporter [#4633](https://github.com/apache/apisix/pull/4633)
- :sunrise: feat(ext-plugin): send the idempotent key when preparing conf [#4736](https://github.com/apache/apisix/pull/4736)

### Bugfix

- fix: the issue that plugins in global rule may be cached to route [#4867](https://github.com/apache/apisix/pull/4867)
- fix(grpc-transcode): support converting nested message [#4859](https://github.com/apache/apisix/pull/4859)
- fix(authz-keycloak): set permissions as empty table when lazy_load_path is false [#4845](https://github.com/apache/apisix/pull/4845)
- fix(proxy-cache): keep cache_method same with nginx's proxy_cache_methods [#4814](https://github.com/apache/apisix/pull/4814)
- fix(admin): inject updatetime when the request is PATCH with sub path [#4765](https://github.com/apache/apisix/pull/4765)
- fix(admin): check username for updating consumer [#4756](https://github.com/apache/apisix/pull/4756)
- fix(error-log-logger): avoid sending stale error log [#4690](https://github.com/apache/apisix/pull/4690)
- fix(grpc-transcode): handle enum type [#4706](https://github.com/apache/apisix/pull/4706)
- fix: when a request caused a 500 error, the status was converted to 405 [#4696](https://github.com/apache/apisix/pull/4696)

## 2.8.0

### Change

- change: enable stream proxy only by default [#4580](https://github.com/apache/apisix/pull/4580)

### Core

- :sunrise: feat: allow user-defined balancer with metadata in node [#4605](https://github.com/apache/apisix/pull/4605)
- :sunrise: feat: Add option retry_timeout that like nginx's proxy_next_upstream_timeout [#4574](https://github.com/apache/apisix/pull/4574)
- :sunrise: feat: enable balancer phase for plugins [#4549](https://github.com/apache/apisix/pull/4549)
- :sunrise: feat: allow setting separate keepalive pool [#4506](https://github.com/apache/apisix/pull/4506)
- :sunrise: feat: enable etcd health-check [#4191](https://github.com/apache/apisix/pull/4191)

### Plugin

- :sunrise: feat: add gzip plugin [#4640](https://github.com/apache/apisix/pull/4640)
- :sunrise: feat(plugin): Add new plugin ua-restriction for bot spider restriction [#4587](https://github.com/apache/apisix/pull/4587)
- :sunrise: feat(stream): add ip-restriction [#4602](https://github.com/apache/apisix/pull/4602)
- :sunrise: feat(stream): add limit-conn [#4515](https://github.com/apache/apisix/pull/4515)
- :sunrise: feat: increase ext-plugin timeout to 60s [#4557](https://github.com/apache/apisix/pull/4557)
- :sunrise: feat(key-auth): supporting key-auth plugin to get key from query string [#4490](https://github.com/apache/apisix/pull/4490)
- :sunrise: feat(kafka-logger): support for specified the log formats via admin API. [#4483](https://github.com/apache/apisix/pull/4483)

### Bugfix

- fix(stream): sni router is broken when session reuses [#4607](https://github.com/apache/apisix/pull/4607)
- fix: the limit-conn plugin cannot effectively intercept requests in special scenarios [#4585](https://github.com/apache/apisix/pull/4585)
- fix: ref check while deleting proto via Admin API [#4575](https://github.com/apache/apisix/pull/4575)
- fix(skywalking): handle conflict between global rule and route [#4589](https://github.com/apache/apisix/pull/4589)
- fix: `ctx.var.cookie_*` cookie not found log [#4564](https://github.com/apache/apisix/pull/4564)
- fix(request-id): we can use different ids with the same request [#4479](https://github.com/apache/apisix/pull/4479)

## 2.7.0

### Change

- change: check metadata_schema with check_schema like the other schema [#4381](https://github.com/apache/apisix/pull/4381)
- change(echo): remove odd auth_value [#4055](https://github.com/apache/apisix/pull/4055)
- fix(admin): correct the resources' count field and change its type to integer [#4385](https://github.com/apache/apisix/pull/4385)

### Core

- :sunrise: feat(stream): support client certificate verification [#4445](https://github.com/apache/apisix/pull/4445)
- :sunrise: feat(stream): accept tls over tcp [#4409](https://github.com/apache/apisix/pull/4409)
- :sunrise: feat(stream): support domain in the upstream [#4386](https://github.com/apache/apisix/pull/4386)
- :sunrise: feat(cli): wrap nginx quit cmd [#4360](https://github.com/apache/apisix/pull/4360)
- :sunrise: feat: allow to set custom timeout for route [#4340](https://github.com/apache/apisix/pull/4340)
- :sunrise: feat: nacos discovery support group [#4325](https://github.com/apache/apisix/pull/4325)
- :sunrise: feat: nacos discovery support namespace [#4313](https://github.com/apache/apisix/pull/4313)

### Plugin

- :sunrise: feat(client-control): set client_max_body_size dynamically [#4423](https://github.com/apache/apisix/pull/4423)
- :sunrise: feat(ext-plugin): stop the runner with SIGTERM [#4367](https://github.com/apache/apisix/pull/4367)
- :sunrise: feat(limit-req) support nodelay [#4395](https://github.com/apache/apisix/pull/4395)
- :sunrise: feat(mqtt-proxy): support domain [#4391](https://github.com/apache/apisix/pull/4391)
- :sunrise: feat(redirect): support appending query string [#4298](https://github.com/apache/apisix/pull/4298)

### Bugfix

- fix: solve memory leak when the client aborts [#4405](https://github.com/apache/apisix/pull/4405)
- fix(etcd): check res.body.error before accessing the data [#4371](https://github.com/apache/apisix/pull/4371)
- fix(ext-plugin): when token is stale, refresh token and try again [#4345](https://github.com/apache/apisix/pull/4345)
- fix(ext-plugin): pass environment variables [#4349](https://github.com/apache/apisix/pull/4349)
- fix: ensure the plugin is always reloaded [#4319](https://github.com/apache/apisix/pull/4319)

## 2.6.0

### Change

- change(prometheus): redesign the latency metrics & update grafana [#3993](https://github.com/apache/apisix/pull/3993)
- change(prometheus): don't expose metrics to internet [#3994](https://github.com/apache/apisix/pull/3994)
- change(limit-count): ensure redis cluster name is set correctly [#3910](https://github.com/apache/apisix/pull/3910)
- change: drop support of OpenResty 1.15 [#3960](https://github.com/apache/apisix/pull/3960)

### Core

- :sunrise: feat: support passing different host headers in multiple nodes [#4208](https://github.com/apache/apisix/pull/4208)
- :sunrise: feat: add 50x html for error page [#4164](https://github.com/apache/apisix/pull/4164)
- :sunrise: feat: support to use upstream_id in stream_route [#4121](https://github.com/apache/apisix/pull/4121)
- :sunrise: feat: support client certificate verification [#4034](https://github.com/apache/apisix/pull/4034)
- :sunrise: feat: add nacos support [#3820](https://github.com/apache/apisix/pull/3820)
- :sunrise: feat: patch tcp.sock.connect to use our DNS resolver [#4114](https://github.com/apache/apisix/pull/4114)

### Plugin

- :sunrise: feat(redirect): support uri encoding [#4244](https://github.com/apache/apisix/pull/4244)
- :sunrise: feat(key-auth): allow customizing header [#4013](https://github.com/apache/apisix/pull/4013)
- :sunrise: feat(response-rewrite): allow using variable in the header [#4194](https://github.com/apache/apisix/pull/4194)
- :sunrise: feat(ext-plugin): APISIX can support Java, Go and other languages to implement custom plugin [#4183](https://github.com/apache/apisix/pull/4183)

### Bugfix

- fix(DNS): support IPv6 resolver [#4242](https://github.com/apache/apisix/pull/4242)
- fix(healthcheck): only one_loop is needed in the passive health check report [#4116](https://github.com/apache/apisix/pull/4116)
- fix(traffic-split): configure multiple "rules", the request will be confused between upstream [#4092](https://github.com/apache/apisix/pull/4092)
- fix: ensure upstream with domain is cached [#4061](https://github.com/apache/apisix/pull/4061)
- fix: be compatible with the router created before 2.5 [#4056](https://github.com/apache/apisix/pull/4056)
- fix(standalone): the conf should be available during start [#4027](https://github.com/apache/apisix/pull/4027)
- fix: ensure atomic operation in limit-count plugin [#3991](https://github.com/apache/apisix/pull/3991)

## 2.5.0

**The changes marked with :warning: are not backward compatible.**
**Please upgrade your data accordingly before upgrading to this version.**
**[#3809](https://github.com/apache/apisix/pull/3809) Means that empty vars will make the route fail to match any requests.**

### Change

- :warning: change: remove unused consumer.id  [#3868](https://github.com/apache/apisix/pull/3868)
- :warning: change: remove deprecated upstream.enable_websocket [#3854](https://github.com/apache/apisix/pull/3854)
- change(zipkin): rearrange the child span [#3877](https://github.com/apache/apisix/pull/3877)

### Core

- :sunrise: feat: support mTLS with etcd [#3905](https://github.com/apache/apisix/pull/3905)
- :warning: feat: upgrade lua-resty-expr/radixtree to support logical expression [#3809](https://github.com/apache/apisix/pull/3809)
- :sunrise: feat: load etcd configuration when apisix starts [#3799](https://github.com/apache/apisix/pull/3799)
- :sunrise: feat: let balancer support priority [#3755](https://github.com/apache/apisix/pull/3755)
- :sunrise: feat: add control api for discovery module [#3742](https://github.com/apache/apisix/pull/3742)

### Plugin

- :sunrise: feat(skywalking):  allow destroy and configure report interval for reporter [#3925](https://github.com/apache/apisix/pull/3925)
- :sunrise: feat(traffic-split): the upstream pass_host needs to support IP mode [#3870](https://github.com/apache/apisix/pull/3870)
- :sunrise: feat: Add filter on HTTP methods for consumer-restriction plugin [#3691](https://github.com/apache/apisix/pull/3691)
- :sunrise: feat: add allow_origins_by_regex to cors plugin [#3839](https://github.com/apache/apisix/pull/3839)
- :sunrise: feat: support conditional response rewrite [#3577](https://github.com/apache/apisix/pull/3577)

### Bugfix

- fix(error-log-logger): the logger should be run in each process [#3912](https://github.com/apache/apisix/pull/3912)
- fix: use the builtin server by default [#3907](https://github.com/apache/apisix/pull/3907)
- fix(traffic-split): binding upstream via upstream_id is invalid [#3842](https://github.com/apache/apisix/pull/3842)
- fix: correct the validation for ssl_trusted_certificate [#3832](https://github.com/apache/apisix/pull/3832)
- fix: don't override cache relative headers [#3789](https://github.com/apache/apisix/pull/3789)
- fix: fail to run `make deps` on macOS [#3718](https://github.com/apache/apisix/pull/3718)

## 2.4.0

### Change

- change: global rules should not be executed on the internal api by default [#3396](https://github.com/apache/apisix/pull/3396)
- change: default to cache DNS record according to the TTL [#3530](https://github.com/apache/apisix/pull/3530)

### Core

- :sunrise: feat: support SRV record [#3686](https://github.com/apache/apisix/pull/3686)
- :sunrise: feat: add dns discovery [#3629](https://github.com/apache/apisix/pull/3629)
- :sunrise: feat: add consul kv discovery module [#3615](https://github.com/apache/apisix/pull/3615)
- :sunrise: feat: support to bind plugin config by `plugin_config_id` [#3567](https://github.com/apache/apisix/pull/3567)
- :sunrise: feat: support listen http2 with plaintext [#3547](https://github.com/apache/apisix/pull/3547)
- :sunrise: feat: support DNS AAAA record [#3484](https://github.com/apache/apisix/pull/3484)

### Plugin

- :sunrise: feat: the traffic-split plugin supports upstream_id [#3512](https://github.com/apache/apisix/pull/3512)
- :sunrise: feat(zipkin): support b3 req header [#3551](https://github.com/apache/apisix/pull/3551)

### Bugfix

- fix(chash): ensure retry can try every node [#3651](https://github.com/apache/apisix/pull/3651)
- fix: script does not work when the route is bound to a service [#3678](https://github.com/apache/apisix/pull/3678)
- fix: use openssl111 in openresty dir in precedence [#3603](https://github.com/apache/apisix/pull/3603)
- fix(zipkin): don't cache the per-req sample ratio [#3522](https://github.com/apache/apisix/pull/3522)

For more changes, please refer to [Milestone](https://github.com/apache/apisix/milestone/13)

## 2.3.0

### Change

- fix: use luajit by default when run apisix [#3335](https://github.com/apache/apisix/pull/3335)
- feat: use luasocket instead of curl in etcd.lua [#2965](https://github.com/apache/apisix/pull/2965)

### Core

- :sunrise: feat: support to communicate with etcd by TLS without verification in command line [#3415](https://github.com/apache/apisix/pull/3415)
- :sunrise: feat: chaos test on route could still works when etcd is down [#3404](https://github.com/apache/apisix/pull/3404)
- :sunrise: feat: ewma use p2c to improve performance [#3300](https://github.com/apache/apisix/pull/3300)
- :sunrise: feat: support specifying https in upstream to talk with https backend [#3430](https://github.com/apache/apisix/pull/3430)
- :sunrise: feat: allow customizing lua_package_path & lua_package_cpath [#3417](https://github.com/apache/apisix/pull/3417)
- :sunrise: feat: allow to pass SNI in HTTPS proxy [#3420](https://github.com/apache/apisix/pull/3420)
- :sunrise: feat: support gRPCS [#3411](https://github.com/apache/apisix/pull/3411)
- :sunrise: feat: allow getting upstream health check status via control API [#3345](https://github.com/apache/apisix/pull/3345)
- :sunrise: feat: support dubbo [#3224](https://github.com/apache/apisix/pull/3224)
- :sunrise: feat: load balance by least connections [#3304](https://github.com/apache/apisix/pull/3304)

### Plugin

- :sunrise: feat: kafka-logger implemented reuse kafka producer [#3429](https://github.com/apache/apisix/pull/3429)
- :sunrise: feat(authz-keycloak): dynamic scope and resource mapping. [#3308](https://github.com/apache/apisix/pull/3308)
- :sunrise: feat: proxy-rewrite host support host with port [#3428](https://github.com/apache/apisix/pull/3428)
- :sunrise: feat(fault-injection): support conditional fault injection using nginx variables [#3363](https://github.com/apache/apisix/pull/3363)

### Bugfix

- fix(standalone): require consumer's id to be the same as username [#3394](https://github.com/apache/apisix/pull/3394)
- fix: support upstream_id & consumer with grpc [#3387](https://github.com/apache/apisix/pull/3387)
- fix: set conf info when global rule is hit without matched rule [#3332](https://github.com/apache/apisix/pull/3332)
- fix: avoid caching outdated discovery upstream nodes [#3295](https://github.com/apache/apisix/pull/3295)
- fix: create the health checker in `access` phase [#3240](https://github.com/apache/apisix/pull/3240)
- fix: make set_more_retries() work when upstream_type is chash [#2676](https://github.com/apache/apisix/pull/2676)

For more changes, please refer to [Milestone](https://github.com/apache/apisix/milestone/12)

## 2.2.0

### Change

- disable node-status plugin by default [#2968](https://github.com/apache/apisix/pull/2968)
- k8s_deployment_info is no longer allowed in upstream [#3098](https://github.com/apache/apisix/pull/3098)
- don't treat route segment with ':' as parameter by default [#3154](https://github.com/apache/apisix/pull/3154)

### Core

- :sunrise: allow create consumers with multiple auth plugins [#2898](https://github.com/apache/apisix/pull/2898)
- :sunrise: increase the delay before resync etcd [#2977](https://github.com/apache/apisix/pull/2977)
- :sunrise: support enable/disable route [#2943](https://github.com/apache/apisix/pull/2943)
- :sunrise: route according to the graphql attributes [#2964](https://github.com/apache/apisix/pull/2964)
- :sunrise: share etcd auth token [#2932](https://github.com/apache/apisix/pull/2932)
- :sunrise: add control API [#3048](https://github.com/apache/apisix/pull/3048)

### Plugin

- :sunrise: feat(limt-count): use 'remote_addr' as default key [#2927](https://github.com/apache/apisix/pull/2927)
- :sunrise: feat(fault-injection): support Nginx variable in abort.body [#2986](https://github.com/apache/apisix/pull/2986)
- :sunrise: feat: implement new plugin `server-info` [#2926](https://github.com/apache/apisix/pull/2926)
- :sunrise: feat: add batch process metrics [#3070](https://github.com/apache/apisix/pull/3070)
- :sunrise: feat: Implement traffic splitting plugin [#2935](https://github.com/apache/apisix/pull/2935)
- :sunrise: feat:  the proxy-rewrite plugin  support pass nginx variable within header [#3144](https://github.com/apache/apisix/pull/3144)
- :sunrise: feat: Make headers to add to request in openid-connect plugin configurable [#2903](https://github.com/apache/apisix/pull/2903)
- :sunrise: feat: support var in upstream_uri on proxy-rewrite plugin [#3139](https://github.com/apache/apisix/pull/3139)

### Bugfix

- basic-auth plugin should run in rewrite phases. [#2905](https://github.com/apache/apisix/pull/2905)
- fixed the non effective config update in http/udp-logger [#2901](https://github.com/apache/apisix/pull/2901)
- always necessary to save the data of the limit concurrency, and release the statistical status in the log phase [#2465](https://github.com/apache/apisix/pull/2465)
- avoid duplicate auto-generated id [#3003](https://github.com/apache/apisix/pull/3003)
- fix: ctx being contaminated due to a new feature of openresty 1.19. **For openresty 1.19 users, it is recommended to upgrade the APISIX version as soon as possible.** [#3105](https://github.com/apache/apisix/pull/3105)
- fix: correct the validation of route.vars [#3124](https://github.com/apache/apisix/pull/3124)

For more changes, please refer to [Milestone](https://github.com/apache/apisix/milestone/10)

## 2.1.0

### Core

- :sunrise: **support ENV variable in configuration.** [#2743](https://github.com/apache/apisix/pull/2743)
- :sunrise: **support TLS connection with etcd.** [#2548](https://github.com/apache/apisix/pull/2548)
- generate create/update_time automatically. [#2740](https://github.com/apache/apisix/pull/2740)
- add a deprecate log for enable_websocket in upstream.[#2691](https://github.com/apache/apisix/pull/2691)
- add a deprecate log for consumer id.[#2829](https://github.com/apache/apisix/pull/2829)
- Added `X-APISIX-Upstream-Status` header to distinguish 5xx errors from upstream or APISIX itself. [#2817](https://github.com/apache/apisix/pull/2817)
- support Nginx configuration snippet. [#2803](https://github.com/apache/apisix/pull/2803)

### Plugin

- :sunrise: **Upgrade protocol to support Apache Skywalking 8.0**[#2389](https://github.com/apache/apisix/pull/2389). So this version only supports skywalking 8.0 protocol. This plugin is disabled by default, you need to modify config.yaml to enable, which is not backward compatible.
- :sunrise: add aliyun sls logging plugin.[#2169](https://github.com/apache/apisix/issues/2169)
- proxy-cache: the cache_zone field in the schema should be optional.[#2776](https://github.com/apache/apisix/pull/2776)
- fix: validate plugin configuration in the DP [#2856](https://github.com/apache/apisix/pull/2856)

### Bugfix

- :bug: fix(etcd): handle etcd compaction.[#2687](https://github.com/apache/apisix/pull/2687)
- fix: move `conf/cert` to `t/certs` and disable ssl by default, which is not backward compatible. [#2112](https://github.com/apache/apisix/pull/2112)
- fix: check decrypt key to prevent lua thread aborted [#2815](https://github.com/apache/apisix/pull/2815)

### Not downward compatible features in future versions

-In the 2.3 release, the consumer will only support user names and discard the id. The consumer needs to manually clean up the id field in etcd, otherwise the schema verification will report an error during use
-In the 2.3 release, opening websocket on upstream will no longer be supported
-In version 3.0, the data plane and control plane will be separated into two independent ports, that is, the current port 9080 will only process data plane requests, and no longer process admin API requests

For more changes, please refer to [Milestone](https://github.com/apache/apisix/milestone/8)

## 2.0.0

This is release candidate.

### Core

- :sunrise: **Migrate from etcd v2 to v3 protocol, which is not backward compatible. Apache APISIX only supports etcd 3.4 and above versions.** [#2036](https://github.com/apache/apisix/pull/2036)
- add labels for upstream object.[#2279](https://github.com/apache/apisix/pull/2279)
- add managed fields in json schema for resources, such as create_time and update_time.[#2444](https://github.com/apache/apisix/pull/2444)
- use interceptors to protect plugin's route[#2416](https://github.com/apache/apisix/pull/2416)
- support multiple ports for http and https listen.[#2409](https://github.com/apache/apisix/pull/2409)
- implement `core.sleep`.[#2397](https://github.com/apache/apisix/pull/2397)

### Plugin

- :sunrise: **add AK/SK(HMAC) auth plugin.**[#2192](https://github.com/apache/apisix/pull/2192)
- :sunrise: add referer-restriction plugin.[#2352](https://github.com/apache/apisix/pull/2352)
- `limit-count` support to use `redis` cluster.[#2406](https://github.com/apache/apisix/pull/2406)
- feat(proxy-cache): store the temporary file under cache directory. [#2317](https://github.com/apache/apisix/pull/2317)
- feat(http-logger): support for specified the log formats via admin API [#2309](https://github.com/apache/apisix/pull/2309)

### Bugfix

- :bug: **`high priority`** When the data plane receives an instruction to delete a resource(router or upstream etc.), it does not properly clean up the cache, resulting in the existing resources cannot be found. This problem only occurs in the case of long and frequent deletion operations.[#2168](https://github.com/apache/apisix/pull/2168)
- fix routing priority does not take effect.[#2447](https://github.com/apache/apisix/pull/2447)
- set random seed for each worker process at `init_worker` phase, only `init` phase is not enough.[#2357](https://github.com/apache/apisix/pull/2357)
- remove unsupported algorithm in jwt plugin.[#2356](https://github.com/apache/apisix/pull/2356)
- return correct response code when `http_to_https` enabled in redirect plugin.[#2311](https://github.com/apache/apisix/pull/2311)

For more changes, please refer to [Milestone](https://github.com/apache/apisix/milestone/7)

### CVE

- Fixed Admin API default access token vulnerability

## 1.5.0

### Core

- Admin API: support authentication with SSL certificates. [1747](https://github.com/apache/apisix/pull/1747)
- Admin API: support both standard `PATCH` and sub path `PATCH`. [1930](https://github.com/apache/apisix/pull/1930)
- HealthCheck: supports custom host port. [1914](https://github.com/apache/apisix/pull/1914)
- Upstream: supports turning off the default retry mechanism. [1919](https://github.com/apache/apisix/pull/1919)
- URI: supports delete the '/' at the end of the `URI`. [1766](https://github.com/apache/apisix/pull/1766)

### New Plugin

- :sunrise: **Request Validator** [1709](https://github.com/apache/apisix/pull/1709)

### Improvements

- change: nginx worker_shutdown_timeout is changed from 3s to recommended value 240s. [1883](https://github.com/apache/apisix/pull/1883)
- change: the `healthcheck` timeout time type changed from `integer` to `number`. [1892](https://github.com/apache/apisix/pull/1892)
- change: the `request-validation` plugin input parameter supports `Schema` validation. [1920](https://github.com/apache/apisix/pull/1920)
- change: add comments for Makefile `install` command. [1912](https://github.com/apache/apisix/pull/1912)
- change: update comment for config.yaml `etcd.timeout` configuration. [1929](https://github.com/apache/apisix/pull/1929)
- change: add more prometheus metrics. [1888](https://github.com/apache/apisix/pull/1888)
- change: add more configuration options for `cors` plugin. [1963](https://github.com/apache/apisix/pull/1963)

### Bugfix

- fixed: failed to get `host` in health check configuration. [1871](https://github.com/apache/apisix/pull/1871)
- fixed: should not save the runtime data of plugin into `etcd`. [1910](https://github.com/apache/apisix/pull/1910)
- fixed: run `apisix start` several times will start multi nginx processes. [1913](https://github.com/apache/apisix/pull/1913)
- fixed: read the request body from the temporary file if it was cached. [1863](https://github.com/apache/apisix/pull/1863)
- fixed: batch processor name and error return type. [1927](https://github.com/apache/apisix/pull/1927)
- fixed: failed to read redis.ttl in `limit-count` plugin. [1928](https://github.com/apache/apisix/pull/1928)
- fixed: passive health check seems never provide a healthy report. [1918](https://github.com/apache/apisix/pull/1918)
- fixed: avoid to modify the original plugin conf. [1958](https://github.com/apache/apisix/pull/1958)
- fixed: the test case of `invalid-upstream` is unstable and sometimes fails to run. [1925](https://github.com/apache/apisix/pull/1925)

### Doc

- doc: added APISIX Lua Coding Style Guide. [1874](https://github.com/apache/apisix/pull/1874)
- doc: fixed link syntax in README.md. [1894](https://github.com/apache/apisix/pull/1894)
- doc: fixed image links in zh-cn benchmark. [1896](https://github.com/apache/apisix/pull/1896)
- doc: fixed typos in `FAQ`、`admin-api`、`architecture-design`、`discovery`、`prometheus`、`proxy-rewrite`、`redirect`、`http-logger` documents. [1916](https://github.com/apache/apisix/pull/1916)
- doc: added improvements for OSx unit tests and request validation plugin. [1926](https://github.com/apache/apisix/pull/1926)
- doc: fixed typos in `architecture-design` document. [1938](https://github.com/apache/apisix/pull/1938)
- doc: added the default import path of `Nginx` for unit testing in `Linux` and `macOS` systems in the `how-to-build` document. [1936](https://github.com/apache/apisix/pull/1936)
- doc: add `request-validation` plugin chinese document. [1932](https://github.com/apache/apisix/pull/1932)
- doc: fixed file path of `gRPC transcoding` in `README`. [1945](https://github.com/apache/apisix/pull/1945)
- doc: fixed `uri-blocker` plugin path error in `README`. [1950](https://github.com/apache/apisix/pull/1950)
- doc: fixed `grpc-transcode` plugin path error in `README`. [1946](https://github.com/apache/apisix/pull/1946)
- doc: removed unnecessary configurations for `k8s` document. [1891](https://github.com/apache/apisix/pull/1891)

## 1.4.1

### Bugfix

- Fix: multiple SSL certificates are configured, but only one certificate working fine. [1818](https://github.com/apache/incubator-apisix/pull/1818)

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

- always specify perl include path when running test cases. [#1097](https://github.com/apache/incubator-apisix/pull/1097)
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

- [Redirect URI](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/redirect.md): Redirect URI plugin. [#732](https://github.com/apache/incubator-apisix/pull/732)
- [Proxy Rewrite](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/proxy-rewrite.md): Supported remove `header` feature. [#658](https://github.com/apache/incubator-apisix/pull/658)
- [Limit Count](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/limit-count.md): Supported global limit count with `Redis Server`.[#624](https://github.com/apache/incubator-apisix/pull/624)

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

- :sunrise: **[support standalone mode](https://github.com/apache/apisix/blob/master/docs/en/latest/deployment-modes.md#standalone)**: using yaml to update configurations of APISIX, more friendly to kubernetes. [#464](https://github.com/apache/incubator-apisix/pull/464)
- :sunrise: **[support stream proxy](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/stream-proxy.md)**. [#513](https://github.com/apache/incubator-apisix/pull/513)
- :sunrise: support consumer bind plugins. [#544](https://github.com/apache/incubator-apisix/pull/544)
- support domain name in upstream, not only IP. [#522](https://github.com/apache/incubator-apisix/pull/522)
- ignored upstream node when it's weight is 0. [#536](https://github.com/apache/incubator-apisix/pull/536)

### Plugins

- :sunrise: **[MQTT Proxy](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/mqtt-proxy.md)**: support to load balance MQTT by `client_id`, both support MQTT 3.1 and 5.0. [#513](https://github.com/apache/incubator-apisix/pull/513)
- [proxy-rewrite](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/proxy-rewrite.md): rewrite uri,
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

- :sunrise: **[gRPC transcoding](https://github.com/apache/apisix/blob/master/docs/en/latest/plugins/grpc-transcode.md)**: supports protocol transcoding so that clients can access your gRPC API by using HTTP/JSON. [#395](https://github.com/apache/incubator-apisix/issues/395)
- :sunrise: **[radix tree router](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/router-radixtree.md)**: The radix tree is used as the default router implementation. It supports the uri, host, cookie, request header, request parameters, Nginx built-in variables, etc. as the routing conditions, and supports common operators such as equal, greater than, less than, etc., more powerful and flexible.**IMPORTANT: This change is not downward compatible. All users who use historical versions need to manually modify their routing to work properly.** [#414](https://github.com/apache/incubator-apisix/issues/414)
- Dynamic upstream supports more parameters, you can specify the upstream uri and host, and whether to enable websocket. [#451](https://github.com/apache/incubator-apisix/pull/451)
- Support for get values from cookies directly from `ctx.var`. [#449](https://github.com/apache/incubator-apisix/pull/449)
- Routing support IPv6. [#331](https://github.com/apache/incubator-apisix/issues/331)

### Plugins

- :sunrise: **[serverless](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/serverless.md)**: With serverless support, users can dynamically run any Lua function on a gateway node. Users can also use this feature as a lightweight plugin.[#86](https://github.com/apache/incubator-apisix/pull/86)
- :sunrise: **support IdP**: Support external authentication services, such as Auth0, okta, etc., users can use this to connect to Oauth2.0 and other authentication methods. [#447](https://github.com/apache/incubator-apisix/pull/447)
- [rate limit](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/limit-conn.md): Support for more restricted keys, such as `X-Forwarded-For` and `X-Real-IP`, and allows users to use Nginx variables, request headers, and request parameters as keys. [#228](https://github.com/apache/incubator-apisix/issues/228)
- [IP black and white list](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/ip-restriction.md) Support IP black and white list for security. [#398](https://github.com/apache/incubator-apisix/pull/398)

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

- :sunrise: **[Health Check and Circuit Breaker](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/tutorials/health-check.md)**: Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability. [#249](https://github.com/apache/incubator-apisix/pull/249)
- Anti-ReDoS(Regular expression Denial of Service). [#252](https://github.com/apache/incubator-apisix/pull/250)
- supported debug mode. [#319](https://github.com/apache/incubator-apisix/pull/319)
- allowed to use different router. [#364](https://github.com/apache/incubator-apisix/pull/364)
- supported to match route by host + uri. [#325](https://github.com/apache/incubator-apisix/pull/325)
- allowed plugins to handler balance phase. [#299](https://github.com/apache/incubator-apisix/pull/299)
- added desc for upstream and service in schema. [#289](https://github.com/apache/incubator-apisix/pull/289)

### Plugins

- :sunrise: **[OpenTracing](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/zipkin.md)**: support Zipkin and Apache SkyWalking. [#304](https://github.com/apache/incubator-apisix/pull/304)
- [JWT auth](https://github.com/apache/apisix/blob/master/docs/en/latest/plugins/jwt-auth.md). [#303](https://github.com/apache/incubator-apisix/pull/303)

### CLI

- support multiple ips of `allow`. [#340](https://github.com/apache/incubator-apisix/pull/340)
- supported real_ip configure in nginx.conf and added functions to get ip and remote ip. [#236](https://github.com/apache/incubator-apisix/pull/236)

### Dashboard

- :sunrise: **add built-in dashboard**. [#327](https://github.com/apache/incubator-apisix/pull/327)

### Test

- support OSX in Travis CI. [#217](https://github.com/apache/incubator-apisix/pull/217)
- installed all of the dependencies to `deps` folder. [#248](https://github.com/apache/incubator-apisix/pull/248)

[Back to TOC](#table-of-contents)
