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
[中文](README_CN.md)

Reference document
==================

* [APISIX Readme](../README.md)
* [Architecture Design](architecture-design.md)
* [Benchmark](benchmark.md)
* [Build development ENV](dev-manual.md)
* [Install Dependencies](install-dependencies.md): How to install dependencies for different OS.
* [Health Check](health-check.md): Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
* Router
    * [radixtree](router-radixtree.md)
* [Stand Alone Model](stand-alone.md): Supports to load route rules from local yaml file, it is more friendly such as under the kubernetes(k8s).
* [Stream Proxy](stream-proxy.md)
* [Admin API](admin-api-cn.md)
* [Changelog](../CHANGELOG.md)
* [Code Style](../CODE_STYLE.md)
* [FAQ](../FAQ.md)

Plugins
=======

* [hot reload](plugins.md): Hot reload without reload service.
* [key-auth](plugins/key-auth.md): User authentication based on Key Authentication.
* [JWT-auth](plugins/jwt-auth-cn.md): User authentication based on [JWT](https://jwt.io/) (JSON Web Tokens) Authentication.
* [HTTPS/TLS](https.md): Dynamic load the SSL Certificate by Server Name Indication (SNI).
* [limit-count](plugins/limit-count.md): Rate limiting based on a "fixed window" implementation.
* [limit-req](plugins/limit-req.md): Request rate limiting and adjustment based on the "leaky bucket" method.
* [limit-conn](plugins/limit-conn.md): Limite request concurrency (or concurrent connections).
* [proxy-rewrite](plugins/proxy-rewrite.md): Rewrite upstream request information.
* [prometheus](plugins/prometheus.md): Expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
* [OpenTracing](plugins/zipkin.md): Supports Zikpin and Apache SkyWalking.
* [grpc-transcode](plugins/grpc-transcoding.md): REST <--> gRPC transcoding。
* [serverless](plugins/serverless-cn.md)：AllowS to dynamically run Lua code at *different* phase in APISIX.
* [ip-restriction](plugins/ip-restriction.md): IP whitelist/blacklist.
* openid-connect
