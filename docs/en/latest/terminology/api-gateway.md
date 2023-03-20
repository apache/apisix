---
title: API Gateway
keywords:
  - Apache APISIX
  - API Gateway
  - Gateway
description: This article mainly introduces the role of the API gateway and why it is needed.
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

An API gateway is a software pattern that sits in front of an application programming interface (API) or group of microservices, to facilitate requests and delivery of data and services. Its primary role is to act as a single entry point and standardized process for interactions between an organization's apps, data, and services and internal and external customers. The API gateway can also perform various other functions to support and manage API usage, from authentication to rate limiting to analytics.

An API gateway also acts as a gateway between the API and the underlying infrastructure. It can be used to route requests to different backends, such as a load balancer, or route requests to different services based on the request headers.

## Why use an API gateway?

An API gateway comes with a lot of benefits over a traditional API microservice. The following are some of the benefits:

- It is a single entry point for all API requests.
- It can be used to route requests to different backends, such as a load balancer, or route requests to different services based on the request headers.
- It can be used to perform authentication, authorization, and rate-limiting.
- It can be used to support analytics, such as monitoring, logging, and tracing.
- It can protect the API from malicious attack vectors such as SQL injections, DDOS attacks, and XSS.
- It decreases the complexity of the API and microservices.
