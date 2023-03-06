---
title: Architecture
keywords:
  - API Gateway
  - Apache APISIX
  - APISIX architecture
description: Architecture of Apache APISIX—the Cloud Native API Gateway.
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

APISIX is built on top of Nginx and [ngx_lua](https://github.com/openresty/lua-nginx-module) leveraging the power offered by LuaJIT. See [Why Apache APISIX chose Nginx and Lua to build API Gateway?](https://apisix.apache.org/blog/2021/08/25/why-apache-apisix-chose-nginx-and-lua/).

![flow-software-architecture](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-software-architecture.png)

APISIX has two main parts:

1. APISIX core, Lua plugin, multi-language Plugin runtime, and the WASM plugin runtime.
2. Built-in Plugins that adds features for observability, security, traffic control, etc.

The APISIX core handles the important functions like matching Routes, load balancing, service discovery, configuration management, and provides a management API. It also includes APISIX Plugin runtime supporting Lua and multilingual Plugins (Go, Java , Python, JavaScript, etc) including the experimental WASM Plugin runtime.

APISIX also has a set of [built-in Plugins](https://apisix.apache.org/docs/apisix/plugins/batch-requests) that adds features like authentication, security, observability, etc. They are written in Lua.

## Here is an overview of the architecture

1.Nginx: APISIX is built on top of Nginx, an open source web server that is known for its high performance and scalability. Nginx acts as a reverse proxy and is responsible for routing the client requests to the appropriate backend service.

2.Lua: APISIX is implemented in Lua, a lightweight programming language that is easy to learn and highly extensible. Lua is used to write plugins and extensions that can be added to APISIX to add custom functionality.

3.Etcd: APISIX uses etcd, a distributed key-value store, to store its configuration data. The configuration data includes information about the backend services, the routes, and the plugins that are used by APISIX.

4.REST API: APISIX provides a REST API that can be used to configure and manage the gateway. The REST API allows developers to add new routes, plugins, and services, as well as modify the existing configuration.

5.Plugin System: APISIX has a plugin system that allows developers to extend the functionality of the gateway. APISIX provides a number of plugins out of the box, such as rate limiting, authentication, and SSL termination, but developers can also create their own custom plugins.

6.Load Balancing: APISIX provides load balancing capabilities out of the box. It can distribute traffic evenly across multiple backend services, improving reliability and scalability.

7.Caching: APISIX has a built-in caching system that can be used to cache responses from backend services. This can improve performance and reduce the load on the backend services.

8.Service Discovery: APISIX can use service discovery systems, such as Consul or ZooKeeper, to automatically discover backend services and configure routing accordingly.

9.Metrics: APISIX provides metrics and monitoring capabilities that can be used to monitor the performance of the gateway and the backend services.

## Request handling process

The diagram below shows how APISIX handles an incoming request and applies corresponding Plugins:

![flow-load-plugin](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-load-plugin.png)
When a request arrives at APISIX, the following steps take place:

APISIX receives the request: When a client sends a request to the API, APISIX receives it and processes it. The request could be an HTTP request or any other protocol that APISIX supports.

Route matching: APISIX checks the incoming request against the configured routes to find a match. Each route is defined by a combination of a URI path, an HTTP method, and any additional criteria, such as headers or query parameters. If a match is found, APISIX proceeds to the next step.

Plugin execution: Once APISIX has identified the correct route, it executes the plugins associated with that route. Plugins can perform a variety of actions, such as authentication, rate limiting, request/response transformation, and more. The plugins are executed in the order specified in the configuration file.

Proxying: After all the plugins have been executed, APISIX proxies the request to the upstream service. The upstream service could be a web application, a microservice, or any other endpoint that can handle the request.

Response processing: When the upstream service returns a response, APISIX processes it according to the plugins associated with the route. Plugins can modify the response, add headers, or perform other actions.

Response delivery: Finally, APISIX delivers the response to the client. If any plugins have modified the response, the modified version is returned to the client.

## Plugin hierarchy

The chart below shows the order in which different types of Plugin are applied to a request:

![flow-plugin-internal](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-plugin-internal.png)
