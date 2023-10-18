---
title: API Gateway
keywords:
  - Apache APISIX
  - API 网关
  - 网关
description: 本文主要介绍了 API 网关的作用以及为什么需要 API 网关。
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

## 描述

API 网关是位于客户端与后端服务集之间的 API 管理工具。API 网关相当于反向代理，用于接受所有 API 的调用、整合处理这些调用所需的各种服务，并返回相应的结果。API 网关通常会处理**跨 API 服务系统使用**的常见任务，并统一接入进行管理。通过 API 网关的统一拦截，可以实现对 API 接口的安全、日志等共性需求，如用户身份验证、速率限制和统计信息。

## 为什么需要 API 网关？

与传统的 API 微服务相比，API 网关有很多好处。比如：

- 它是所有 API 请求的唯一入口。
- 可用于将请求转发到不同的后端，或根据请求头将请求转发到不同的服务。
- 可用于执行身份验证、授权和限速。
- 它可用于支持分析，例如监控、日志记录和跟踪。
- 可以保护 API 免受 SQL 注入、DDOS 攻击和 XSS 等恶意攻击媒介的攻击。
- 它可以降低 API 和微服务的复杂性。
