---
title: APISIX variable
keywords:
 - Apache APISIX
 - API Gateway
 - APISIX variable
description: This is article descriptions Apache APISIX variable.
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

Besides [Nginx variable](http://nginx.org/en/docs/varindex.html), APISIX also provides
additional variables.

## List of variables

|   Variable Name     |  Origin    | Description                                                                         | Example        |
|-------------------- | ---------- | ----------------------------------------------------------------------------------- | -------------  |
| balancer_ip         | core       | the IP of picked upstream server.                                                   | 192.168.1.2    |
| balancer_port       | core       | the port of picked upstream server.                                                 | 80             |
| consumer_name       | core       | username of Consumer.                                                               |                |
| graphql_name        | core       | the [operation name](https://graphql.org/learn/queries/#operation-name) of GraphQL. | HeroComparison |
| graphql_operation   | core       | the operation type of GraphQL.                                                      | mutation       |
| graphql_root_fields | core       | the top level fields of GraphQL.                                                    | ["hero"]       |
| mqtt_client_id      | mqtt-proxy | the client id in MQTT protocol.                                                     |                |
| route_id            | core       | id of Route.                                                                        |                |
| route_name          | core       | name of Route.                                                                      |                |
| service_id          | core       | id of Service.                                                                      |                |
| service_name        | core       | name of Service.                                                                    |                |
| redis_cmd_line      | Redis      | the content of Redis command.                                                       |                |
| rpc_time            | xRPC       | time spent at the rpc request level.                                                |                |

You can also register your own [variable](./plugin-develop.md#register-custom-variable).
