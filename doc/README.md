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
[Chinese](README_CN.md)

Reference Documentation
==================

* [APISIX Readme](../README.md)
* [Architecture Design](architecture-design.md)
* [Benchmark](benchmark.md)
* [Getting Started Guide](getting-started.md)
* [How to build Apache APISIX](how-to-build.md)
* [Health Check](health-check.md): Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
* Router
    * [radixtree](router-radixtree.md)
* [Stand Alone Model](stand-alone.md): Supports to load route rules from local yaml file, it is more friendly such as under the kubernetes(k8s).
* [Stream Proxy](stream-proxy.md)
* [Admin API](admin-api.md)
* [Changelog](../CHANGELOG.md)
* [Code Style](../CODE_STYLE.md)
* [FAQ](../FAQ.md)

Plugins
=======

* [hot reload](plugins.md): Hot reload without reload service.
* [key-auth](plugins/key-auth.md): User authentication based on Key Authentication.
* [JWT-auth](plugins/jwt-auth.md): User authentication based on [JWT](https://jwt.io/) (JSON Web Tokens) Authentication.
* [basic-auth](doc/plugins/basic-auth.md): User authentication based on Basic Authentication.
* [HTTPS/TLS](https.md): Dynamic load the SSL Certificate by Server Name Indication (SNI).
* [limit-count](plugins/limit-count.md): Rate limiting based on a "fixed window" implementation.
* [limit-req](plugins/limit-req.md): Request rate limiting and adjustment based on the "leaky bucket" method.
* [limit-conn](plugins/limit-conn.md): Limite request concurrency (or concurrent connections).
* [proxy-rewrite](plugins/proxy-rewrite.md): Rewrite upstream request information.
* [prometheus](plugins/prometheus.md): Expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
* [OpenTracing](plugins/zipkin.md): Supports Zikpin and Apache SkyWalking.
* [grpc-transcode](plugins/grpc-transcoding.md): REST <--> gRPC transcoding.
* [serverless](plugins/serverless.md)：Allows to dynamically run Lua code at *different* phase in APISIX.
* [ip-restriction](plugins/ip-restriction.md): IP whitelist/blacklist.
* [openid-connect](plugins/oauth.md)
* [redirect](plugins/redirect.md): URI redirect.
* [response-rewrite](plugins/response-rewrite.md): Set customized response status code, body and header to the client.
* fault injection：The specified response body, response code, and response time can be returned, which provides processing capabilities in different failure scenarios, such as service failure, service overload, and high service delay.

Deploy to the Cloud
=======
### AWS

The recommended approach is to deploy APISIX with [AWS CDK](https://aws.amazon.com/cdk/) on [AWS Fargate](https://aws.amazon.com/fargate/) which helps you decouple the APISIX layer and the upstream layer on top of a fully-managed and secure serverless container compute environment with autoscaling capabilities.

See [this guide](https://github.com/pahud/cdk-samples/blob/master/typescript/apisix/README.md) by [Pahud Hsieh](https://github.com/pahud) and learn how to provision the recommended architecture 100% in AWS CDK.
