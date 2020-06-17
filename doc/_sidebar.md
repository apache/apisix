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

- Getting started

  - [Introduction](README.md)
  - [Quick start](getting-started.md)

- General

  - [Architecture](architecture-design.md)

  - [Benchmark](benchmark.md)

  - Installation

     - [How to build](how-to-build.md)
     - [Install Dependencies](install-dependencies.md)

  - [HTTPS](https.md)

  - [Router](router-radixtree.md)

  - Plugins

    - [Develop Plugins](plugin-develop.md)
    - [Hot Reload](plugins.md)

  - Proxy Modes

    - [GRPC Proxy](grpc-proxy.md)
    - [Stream Proxy](stream-proxy.md)

- Plugins

  - Authentication

    - [Key Auth](plugins/key-auth.md)
    - [Basic Auth](plugins/basic-auth.md)
    - [JWT Auth](plugins/jwt-auth.md)
    - [Opend ID Connect](plugins/oauth.md)

  - General

    - [Redirect](plugins/redirect.md)
    - [Serverless](plugins/serverless.md)
    - [Batch Request](plugins/batch-requests.md)
    - [Fault Injection](plugins/fault-injection.md)
    - [MQTT Proxy](plugins/mqtt-proxy.md)
    - [Proxy Cache](plugins/proxy-cache.md)
    - [Proxy Mirror](plugins/proxy-mirror.md)
    - [Echo](plugins/echo.md)

  - Transformations

    - [Response Rewrite](plugins/response-rewrite.md)
    - [Proxy Rewrite](plugins/proxy-rewrite.md)
    - [GRPC Transcoding](plugins/grpc-transcode.md)

  - Security

    -  [Consumer Restriction](plugins/consumer-restriction.md)
    -  [Limit Connection](plugins/limit-conn.md)
    -  [Limit Count](plugins/limit-count.md)
    -  [Limit Request](plugins/limit-req.md)
    -  [CORS](plugins/cors.md)
    -  [IP Restriction](plugins/ip-restriction.md)
    -  [Keycloak Authorization](plugins/authz-keycloak.md)
    -  [RBAC Wolf](plugins/wolf-rbac.md)

  - Monitoring

    - [Prometheus](plugins/prometheus.md)
    - [SKywalking](plugins/skywalking.md)
    - [Zipkin](plugins/zipkin.md)

  - Loggers

    - [HTTP Logger](plugins/http-logger.md)
    - [Kafka Logger](plugins/kafka-logger.md)
    - [Syslog](plugins/syslog.md)
    - [TCP Logger](plugins/tcp-logger.md)
    - [UDP Logger](plugins/udp-logger.md)

- Admin API

  - [Admin API](admin-api.md)
