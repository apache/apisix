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

[中文](plugins-cn.md)

## Plugins

Now we support the following plugins:

* [HTTPS](https.md): dynamic load the SSL Certificate by Server Name Indication (SNI).
* [dynamic load balancing](#Plugins): load balance traffic across multiple upstream services, supports round-robin and consistent hash algorithms.
* [key-auth](plugins/key-auth.md): user authentication based on Key Authentication.
* [JWT-auth](plugins/jwt-auth-cn.md): user authentication based on [JWT](https://jwt.io/) (JSON Web Tokens) Authentication.
* [limit-count](plugins/limit-count.md): rate limiting based on a "fixed window" implementation.
* [limit-req](plugins/limit-req.md): request rate limiting and adjustment based on the "leaky bucket" method.
* [limit-conn](plugins/limit-conn.md): limite request concurrency (or concurrent connections).
* [prometheus](plugins/prometheus.md): expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
* [OpenTracing](plugins/zipkin.md): support Zikpin and Apache SkyWalking.
* [grpc-transcode](plugins/grpc-transcode-cn.md): REST <--> gRPC transcoding。
* [serverless](plugins/serverless-cn.md)：allow to dynamically run Lua code at *different* phase in APISIX.
* [ip-restriction](plugins/ip-restriction.md): IP whitelist/blacklist.
* openid-connect
