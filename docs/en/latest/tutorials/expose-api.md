---
title: Expose API
keywords:
  - API Gateway
  - Apache APISIX
  - Expose Service
description: This article describes how to publish services through the API Gateway Apache APISIX.
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

This article will guide you through APISIX's upstream, routing, and service concepts and introduce how to publish your services through APISIX.

## Concept introduction

### Upstream

[Upstream](../terminology/upstream.md) is a virtual host abstraction that performs load balancing on a given set of service nodes according to the configured rules.

The role of the Upstream is to load balance the service nodes according to the configuration rules, and Upstream information can be directly configured to the Route or Service.

When multiple routes or services refer to the same upstream, you can create an upstream object and use the upstream ID in the Route or Service to reference the upstream to reduce maintenance pressure.

### Route

[Routes](../terminology/route.md) match the client's request based on defined rules, load and execute the corresponding plugins, and forwards the request to the specified Upstream.

### Service

A [Service](../terminology/service.md) is an abstraction of an API (which can also be understood as a set of Route abstractions). It usually corresponds to an upstream service abstraction.

## Prerequisites

Please make sure you have [installed Apache APISIX](../installation-guide.md) before doing the following.

## Expose your service

1. Create an Upstream.

Create an Upstream service containing `httpbin.org` that you can use for testing. This is a return service that will return the parameters we passed in the request.

```
curl "http://127.0.0.1:9180/apisix/admin/upstreams/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

In this command, we specify the Admin API Key of Apache APISIX as `edd1c9f034335f136f87ad84b625c8f1`, use `roundrobin` as the load balancing mechanism, and set `httpbin.org:80` as the upstream service. To bind this upstream to a route, `upstream_id` needs to be set to `1` here. Here you can specify multiple upstreams under `nodes` to achieve load balancing.

For more information, please refer to [Upstream](../terminology/upstream.md).

2. Create a Route.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream_id": "1"
}'
```

:::note

Adding an `upstream` object to your route can achieve the above effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

:::

3. Test

After creating the Route, you can test the Service with the following command:

```
curl -i -X GET "http://127.0.0.1:9080/anything/get?foo1=bar1&foo2=bar2" -H "Host: example.com"
```

APISIX will forward the request to `http://httpbin.org:80/anything/get?foo1=bar1&foo2=bar2`.

## More Tutorials

You can refer to [Protect API](./protect-api.md) to protect your API.

You can also use APISIX's [Plugin](../terminology/plugin.md) to achieve more functions.
