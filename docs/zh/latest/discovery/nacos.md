---
标题: 集成Nacos作为服务发现中心
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

* [**摘要**](#摘要)
* [**如何在APISIX中使用Nacos**](#如何在APISIX中使用Nacos)
    * [**接入**](#接入)
    * [**upstream 配置**](#upstream-配置)

## 摘要

常见的服务注册发现中心有：Eureka, Etcd, Consul, Zookeeper, Nacos等

目前APISIX官方支持 Eureka 和基于 DNS 的服务注册发现，如 Consul 等，并实现了Eureka的接入代码。参看 [APISIX服务发现](https://github.com/apache/apisix/blob/master/docs/zh/latest/discovery.md)

本文描述了在APISIX中如何使用Nacos作为注册中心

## 如何在APISIX中使用Nacos

### 接入

首先，确保 `apisix/discovery/` 目录中包含 `nacos.lua`；

然后，在 `conf/config.yaml` 增加如下格式的配置：

```yaml
discovery:                     
  nacos:
    host:                     # Nacos集群中可能有多个host.
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

username和password用来获取Nacos的access_token，它的ttl是18000s。

### upstream 配置

这里是一个例子，路由请求"/ping"，到Nacos中注册的服务（该服务的Namespace是dev，group是DEFAULT_GROUP，服务名称是ping_demo)。

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
**服务名称说明**

在Nacos中定位一个服务是从namespace、group和service三个维度进行的。所以service_name里面可以同时传入三个维度的值，格式：`namespaceId:groupName:serviceName`

Nacos的默认namespaceId是public，默认groupName是DEFAULT_GROUP；

当service_name中，仅有一个`:`时，表示`namespaceId:serviceName`，此时groupName是DEFAULT_GROUP

当service_name中，没有`:`时，表示`serviceName`，此时namespaceId是public，groupName是DEFAULT_GROUP
