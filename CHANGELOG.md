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

- :sunrise: **[support stand-alone mode](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/stand-alone-cn.md)**: using yaml to update configurations of APISIX, more friendly to kubernetes. [#464](https://github.com/apache/incubator-apisix/pull/464)
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

- :sunrise: **[gRPC transcoding](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/grpc-transcoding.md)**: supports protocol transcoding so that clients can access your gRPC API by using HTTP/JSON. [#395](https://github.com/apache/incubator-apisix/issues/395)
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

- :sunrise: **[Health Check and Circuit Breaker](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/health-check.md)**: Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability. [#249](https://github.com/apache/incubator-apisix/pull/249)
- Anti-ReDoS(Regular expression Denial of Service). [#252](https://github.com/apache/incubator-apisix/pull/250)
- supported debug mode. [#319](https://github.com/apache/incubator-apisix/pull/319)
- allowed to use different router. [#364](https://github.com/apache/incubator-apisix/pull/364)
- supported to match route by host + uri. [#325](https://github.com/apache/incubator-apisix/pull/325)
- allowed plugins to handler balance phase. [#299](https://github.com/apache/incubator-apisix/pull/299)
- added desc for upstream and service in schema. [#289](https://github.com/apache/incubator-apisix/pull/289)

### Plugins

- :sunrise: **[OpenTracing](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/zipkin.md)**: support Zipkin and Apache SkyWalking. [#304](https://github.com/apache/incubator-apisix/pull/304)
- [JWT auth](https://github.com/apache/incubator-apisix/blob/master/docs/en/latest/plugins/jwt-auth-cn.md). [#303](https://github.com/apache/incubator-apisix/pull/303)

### CLI

- support multiple ips of `allow`. [#340](https://github.com/apache/incubator-apisix/pull/340)
- supported real_ip configure in nginx.conf and added functions to get ip and remote ip. [#236](https://github.com/apache/incubator-apisix/pull/236)

### Dashboard

- :sunrise: **add built-in dashboard**. [#327](https://github.com/apache/incubator-apisix/pull/327)

### Test

- support OSX in Travis CI. [#217](https://github.com/apache/incubator-apisix/pull/217)
- installed all of the dependencies to `deps` folder. [#248](https://github.com/apache/incubator-apisix/pull/248)

[Back to TOC](#table-of-contents)
