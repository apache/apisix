---
title: APISIX 变量
keywords:
 - Apache APISIX
 - API 网关
 - APISIX variable
description: 本文介绍了 Apache APISIX 支持的变量。
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

APISIX 除了支持 [NGINX 变量](http://nginx.org/en/docs/varindex.html)外，自身也提供了一些变量。

## 变量列表

|    变量名称         |  来源       | 描述                                                                             | 示例              |
|---------------------|----------- |--------------------------------------------------------------------------------- | ---------------- |
| balancer_ip         | core       | 上游服务器的 IP 地址。                                                            | 192.168.1.2      |
| balancer_port       | core       | 上游服务器的端口。                                                                | 80               |
| consumer_name       | core       | 消费者的名称。                                                                    |                  |
| consumer_group_id   | core       | 消费者所在的组的 ID。                                                            |                  |
| graphql_name        | core       | GraphQL 的 [operation name](https://graphql.org/learn/queries/#operation-name)。 | HeroComparison   |
| graphql_operation   | core       | GraphQL 的操作类型。                                                              | mutation         |
| graphql_root_fields | core       | GraphQL 最高级别的字段。                                                          | ["hero"]          |
| mqtt_client_id      | mqtt-proxy | MQTT 协议中的客户端 ID。                                                          |                   |
| route_id            | core       | APISIX 路由的 ID。                                                                |                   |
| route_name          | core       | APISIX 路由的名称。                                                               |                   |
| service_id          | core       | APISIX 服务的 ID。                                                                |                   |
| service_name        | core       | APISIX 服务的名称。                                                               |                   |
| redis_cmd_line      | Redis      | Redis 命令的内容。                                                                |                   |
| resp_body           | core       | 在 logger 插件中，如果部分插件支持记录响应的 body 信息，比如配置 `include_resp_body: true`，那可以在 log format 中使用该变量。|                   |
| rpc_time            | xRPC       | 在 RPC 请求级别所花费的时间。                                                      |                   |

当然，除上述变量外，你也可以创建自定义[变量](./plugin-develop.md#register-custom-variable)。
