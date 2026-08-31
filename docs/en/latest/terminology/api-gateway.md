---
title: API Gateway
keywords:
  - Apache APISIX
  - API Gateway
  - Gateway
description: Learn what an API gateway does, where it fits in an API architecture, and which responsibilities remain with services and other infrastructure.
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

## Description

An API gateway is a reverse-proxy component placed between API clients and upstream services. It matches incoming requests, selects an upstream, and proxies the request and response across that boundary. A deployment can use one public gateway, several gateways by region or environment, or a gateway dedicated to a particular application audience.

Depending on the product and enabled policies, an API gateway can also perform authentication, traffic limiting, request or response transformation, observability, and other cross-cutting functions. These capabilities are not enabled automatically and do not replace service-level authorization, data validation, workflow state, or business logic.

## Why use an API gateway?

An API gateway can provide:

- a controlled entry point for selected APIs;
- routing and load balancing across upstream services;
- consistent enforcement of configured authentication and traffic policies;
- protocol- and request-level telemetry at the gateway boundary; and
- a place to apply shared transformations when their ownership and failure behavior are clear.

The gateway is one component in the request path. A service must still authorize access to its resources and enforce business invariants. Rate limiting can reduce abusive traffic but does not, by itself, provide complete denial-of-service protection. Request filtering also does not make an upstream safe from every injection or application vulnerability.

## API gateway in Apache APISIX

Apache APISIX matches [Routes](./route.md), selects [Upstreams](./upstream.md), and runs explicitly configured [plugins](https://apisix.apache.org/plugins/) on the request path. Its topology and configuration source depend on the selected [deployment mode](../deployment-modes.md), including traditional, decoupled, and standalone modes.

For implementation details, see the [APISIX architecture](../architecture-design/apisix.md) and [getting started guide](../getting-started/README.md).
