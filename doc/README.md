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

* [Chinese](./zh-cn/README.md)

## Reference Documentation

* [APISIX Readme](./README.md)
* [Architecture Design](architecture-design.md)
* [Getting Started Guide](getting-started.md)
* [How to build Apache APISIX](how-to-build.md)
* [Admin API](admin-api.md)
* [Control API](control-api.md)
* [Health Check](health-check.md): Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
* [Router radixtree](router-radixtree.md)
* [Stand Alone Model](stand-alone.md): Supports to load route rules from local yaml file, it is more friendly such as under the kubernetes(k8s).
* [Stream Proxy](stream-proxy.md)
* [gRPC Proxy](grpc-proxy.md)
* [Customize Nginx Configuration](./customize-nginx-configuration.md)
* [Changelog](../CHANGELOG.md)
* [Benchmark](benchmark.md)
* [Code Style](../CODE_STYLE.md)
* [Debug Function](./debug-function.md)
* [FAQ](../FAQ.md)

## Plugins

### General

* [batch-requests](plugins/batch-requests.md): Allow you send multiple http api via **http pipeline**.
* [hot reload](plugins.md): Hot reload without reload service.
* [HTTPS/TLS](https.md): Dynamic load the SSL Certificate by Server Name Indication (SNI).
* [serverless](plugins/serverless.md)：Allows to dynamically run Lua code at *different* phase in APISIX.
* [redirect](plugins/redirect.md): URI redirect.

### Transformation

* [response-rewrite](plugins/response-rewrite.md): Set customized response status code, body and header to the client.
* [proxy-rewrite](plugins/proxy-rewrite.md): Rewrite upstream request information.
* [grpc-transcode](plugins/grpc-transcode.md): REST <--> gRPC transcoding.
* [fault-injection](plugins/fault-injection.md): The specified response body, response code, and response time can be returned, which provides processing capabilities in different failure scenarios, such as service failure, service overload, and high service delay.

### Authentication

* [key-auth](plugins/key-auth.md): User authentication based on Key Authentication.
* [JWT-auth](plugins/jwt-auth.md): User authentication based on [JWT](https://jwt.io/) (JSON Web Tokens) Authentication.
* [basic-auth](plugins/basic-auth.md): User authentication based on Basic Authentication.
* [authz-keycloak](plugins/authz-keycloak.md): Authorization with Keycloak Identity Server.
* [wolf-rbac](plugins/wolf-rbac.md) User Authentication and Authorization based on *RBAC*.
* [openid-connect](plugins/openid-connect.md)

### Security

* [cors](plugins/cors.md): Enable CORS(Cross-origin resource sharing) for your API.
* [uri-blocker](plugins/uri-blocker.md): Block client request by URI.
* [ip-restriction](plugins/ip-restriction.md): IP whitelist/blacklist.
* [referer-restriction](plugins/referer-restriction.md): Referer whitelist.

### Traffic

* [limit-req](plugins/limit-req.md): Request rate limiting and adjustment based on the "leaky bucket" method.
* [limit-conn](plugins/limit-conn.md): Limit request concurrency (or concurrent connections).
* [limit-count](plugins/limit-count.md): Rate limiting based on a "fixed window" implementation.
* [proxy-cache](plugins/proxy-cache.md): Provides the ability to cache upstream response data.
* [request-validation](plugins/request-validation.md): Validates requests before forwarding to upstream.
* [proxy-mirror](plugins/proxy-mirror.md): Provides the ability to mirror client requests.
* [api-breaker](plugins/api-breaker.md): Circuit Breaker for API that stops requests forwarding to upstream in case of unhealthy state.
* [traffic-split](plugins/traffic-split.md): Allows users to incrementally direct percentages of traffic between various upstreams.

### Monitoring

* [prometheus](plugins/prometheus.md): Expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
* [OpenTracing](plugins/zipkin.md): Supports Zikpin and Apache SkyWalking.
* [Skywalking](plugins/skywalking.md): Supports Apache SkyWalking.

### Loggers

* [http-logger](plugins/http-logger.md): Log requests to http servers.
* [tcp-logger](plugins/tcp-logger.md): Log requests to TCP servers.
* [kafka-logger](plugins/kafka-logger.md): Log requests to External Kafka servers.
* [udp-logger](plugins/udp-logger.md): Log requests to UDP servers.
* [sys-log](plugins/syslog.md): Log requests to Syslog.
* [log-rotate](plugins/log-rotate.md): Rotate access/error log files.

## Deploy

### AWS

The recommended approach is to deploy APISIX with [AWS CDK](https://aws.amazon.com/cdk/) on [AWS Fargate](https://aws.amazon.com/fargate/) which helps you decouple the APISIX layer and the upstream layer on top of a fully-managed and secure serverless container compute environment with autoscaling capabilities.

### Kubernetes

See [this guide](../kubernetes/README.md) and learn how to deploy apisix in Kubernetes.
