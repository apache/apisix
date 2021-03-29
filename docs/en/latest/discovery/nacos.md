---
title: Integration Nacos service discovery registry
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

* [**Summary**](#Summary)
* [**How to use Nacos in APISIX**](#How-to-use-Nacos-in-APISIX)
    * [**Usage**](#Usage)
    * [**Upstream setting**](#Upstream-setting)

## Summary

Common registries: Eureka, Etcd, Consul, Zookeeper, Nacos etc.

Currently we support Eureka/Consul and serivce discovery via DNS. Reference [discovery](https://github.com/apache/apisix/blob/master/docs/en/latest/discovery.md)

Here we discribe how to use Nacos as service discovery registry in APISIX.

## How to use Nacos in APISIX

### Usage

At first, make sure that `apisix/discovery/` directory contains `nacos.lua`;

Then, add following configuration in `conf/config.yaml`.

```yaml
discovery:                     
  nacos:
    host:                     # it's possible to define multiple nacos hosts addresses of the same nacos cluster.
      - "http://{nacos_host1}:${nacos_port1}"
      - "http://{nacos_host2}:${nacos_port2}"
    username: ${nacos_username}
    password: ${nacos_password}
    prefix: "/nacos/v1/"
    fetch_interval: 5           
    weight: 100                 
    timeout:
      connect: 2000             
      send: 2000               
      read: 5000               
```

The username and the password is used to fetch access_token in Nacos, whose ttl is 18000s. 

### Upstream setting

Here is an example of routing a request with a URL of "/ping" to a service which has namespace "dev", group "DEFAULT_GROUP" and name "ping_demo" with Nacos :

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/ping",
    "upstream": {
        "name": "ping",
        "service_name": "dev:DEFAULT_GROUP:ping_demo",
        "type": "roundrobin",
        "discovery_type": "nacos"
    }
}'
```
**About service name**

In Nacos, namespaceId, groupName and serviceName could be used together to confirm one specific sercie. 

As a result, service_name format like: `namespaceId:groupName:serviceName`.

In Nacos, the default namespaceId is public, and the default groupName is DEFAULT_GROUP.

When service_name contains only one`:` like `namespaceId:serviceName`, the groupName is DEFAULT_GROUP.

When service_name contains no `:` like `serviceName`, the namespaceId is public and groupName is DEFAULT_GROUP.
