---
title: Configure Routes
slug: /getting-started/configure-routes
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/configure-routes" />
</head>

> The Getting Started tutorials are contributed by [API7.ai](https://api7.ai/) and are licensed under the Apache 2.0 license.

Apache APISIX provides flexible gateway management capabilities based on _routes_, where routing paths and targets are defined for requests.

This tutorial guides you on how to create a route and validate it. You will complete the following steps:

1. Create a route with a sample _upstream_ that points to [httpbin.org](http://httpbin.org).
2. Use _cURL_ to send a test request to see how APISIX proxies and forwards the request.

## What is a Route

A route is a routing path to upstream targets. In [Apache APISIX](https://api7.ai/apisix), routes are responsible for matching client's requests based on defined rules, loading and executing the corresponding plugins, as well as forwarding requests to the specified upstream services.

In APISIX, a simple route can be set up with a path-matching URI and a corresponding upstream address.

## What is an Upstream

An upstream is a set of target nodes with the same work. It defines a virtual host abstraction that performs load balancing on a given set of service nodes according to the configured rules.

## Prerequisite(s)

1. Complete [Get APISIX](./) to install APISIX.

## Create a Route

In this section, you will create a route that forwards client requests to [httpbin.org](http://httpbin.org), a public HTTP request and response service.

The following command creates a route, which should forward all requests sent to `http://127.0.0.1:9080/ip` to [httpbin.org/ip](http://httpbin.org/ip):

[//]: <TODO: Add the link to the authorization of Admin API>

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "getting-started-ip",
  "uri": "/ip",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

You will receive an `HTTP/1.1 201 OK` response if the route was created successfully.

## Validate

```shell
curl "http://127.0.0.1:9080/ip"
```

The expected response is similar to the following:

```text
{
  "origin": "183.94.122.205"
}
```

## What's Next

This tutorial creates a route with only one target node. In the next tutorial, you will learn how to configure load balancing with multiple target nodes.
