---
title: Load Blancing
keywords:
  - API Gateway
  - Apache APISIX
  - Load Balancing
description: This article introduces the four load balancing algorithms supported by APISIX and how to use them.
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

APISIX supports configuration of four load balancing algorithms: Round Robin, CHash, least conn, EWMA. In addition, you can also use a custom load balancing algorithm in the balancer stage.

When configuring the upstream, the `type` parameter is used to specify the load balancing algorithm, and the default is the weighted round robin algorithm. For more information, see [Admin API Upstream Object](../admin-api.md#upstream).

## Round Robin

The principle of the polling algorithm is to assign the user's requests to the internal servers in sequence, from the first server to the end of the last server, and the number of requests processed by all servers is consistent. The weighted round-robin is based on the basic round-robin scheduling and assigns a weight to each node. The scheduling ratio of the node is equal to the weight ratio. The greater the weight, the more times it is scheduled.

### Scenes

In the actual production environment, the upstream cluster will be deployed on servers with different performances. If the basic round-robin scheduling is adopted, the proportion of each server being scheduled is the same. At this time, a problem will arise. High-performance servers cannot take advantage of performance, and low-performance servers may over-carry traffic, resulting in significant delays and even downtime.

Therefore, users are required to deploy the cluster on servers with the same performance in order to maximize the performance of the server, but this cannot be achieved in the actual environment.

The emergence of weighted round robin is to solve the above problems. When using the weighted round-robin algorithm, users can set the proportion of upstream nodes to be scheduled according to the performance of the upstream server or other requirements. It can be seen from the above introduction that the weighted round robin algorithm is suitable for HTTP short connection services.

### Feature

Ordinary weighted polling has certain deficiencies in calling. For example, the load capacity ratio of the three servers, A, B, and C, is 3:2:1, and the configured weights are 3, 2, and 1, respectively. Such scheduling may occur Sequence: {A, A, A, B, B, C}.

There will be a problem with this scheduling sequence. A particular node will be centrally scheduled in a short time, causing the node load to be too high. When it is not scheduled, the load is very low. Therefore, regular traffic peaks and valleys can be seen during observation.

However, APISIX uses a smooth, weighted round-robin algorithm, and the scheduling will not be concentrated on the same high-weight node in a short period.

## CHash

Consistent hashing constructs a hash ring and uses a hash algorithm to calculate the mapped upstream node according to the key in the client request. The same key will always return the same upstream node in the same upstream object.

### Scenes

When using APISIX, sometimes it is necessary to ensure session stickiness - forwarding requests with the same characteristics to the same upstream node because these requests with the same features are likely to come from the same user and need to be processed in the same upstream node.
The traditional load-balancing algorithm cannot realize this scenario. You can now use the Chash algorithm to realize the above scenario. Because the consistent hash algorithm can be allocated according to the client IP that initiates the request or a certain value in the request parameter, and requests with the same characteristics are allocated to the same upstream node. E.g:

- Cookie or Session → identity
- IP → location

Chash is also suitable for use in scenarios where the upstream is a distributed cluster. It can avoid data skew and allow a large number of requests to be allocated to a small number of nodes.

### Feature

Consistent hashing in APISIX can specify keys based on NGINX built-in variables. Currently supported NGINX built-in variables are `uri`, `server_name`, `server_addr`, `request_uri`, `remote_port`, `remote_addr`, `query_string`, `host`, `hostname`, `arg_***`, where `arg_***` are the request parameters from the URL.

The following example shows the specific usage of the APISIX consistent hashing algorithm. Create a route and configure it as follows. The configured `key` is `remote_addr,` which is the client IP. It is possible to observe whether requests are proxied to different upstream nodes when the client IP is always the same.

:::note

When using the consistent hash load balancing algorithm, it is recommended that the weights of the upstream nodes be consistent to prevent different weights from interfering with the results of the consistent hash algorithm.

The library used for the hash algorithm is [lua-resty-chash](https://github.com/openresty/lua-resty-balancer).

:::

## Weighted Least Connection

The least number of connections algorithm is an intelligent and dynamic load balancing algorithm, which mainly decides which node to forward the request to according to the current number of connections of each node in the upstream, that is, each time the request is forwarded to the node that currently has the least concurrent connections .

The weighted least number of connections refers to selecting the node with the smallest `(active_conn + 1) / weight`. Usually, the upstream node with the largest weight and the least number of concurrent connections will be called first.

:::note

`active_conn` indicates the connection currently being used by the request.

:::

### Scenes

In actual scenarios, the same upstream node will provide many APIs with different business logic, so the time consumed to process requests is also different. When the service is running, if an API in the upstream suddenly floods with requests, it will experience high latency.

From the perspective of APISIX, the faster the upstream node processes the request, the fewer `active_conn` between APISIX and the node. Because this node quickly processes the request, and the connection is released.

As the running time continues to increase, if some requests take a long time to process, the load on the upstream node where the request is located will be high. Therefore, according to the request processing time (for APISIX, it is the connection currently being used by request), the request is forwarded to the upstream node with less `active_conn`, which can avoid the accumulation of a large number of time-consuming requests on high-load nodes, thereby achieving Optimize the effect of load balancing.

This algorithm is suitable for the request service that must be processed for a long time, and the backend time occupied by each request varies greatly. That is, the long-term connection service.

### Feature

The Weighted Least Connection algorithm can dynamically distribute requests according to a load of upstream nodes, so the server has strong performance and fast request processing speed, and upstream nodes with fewer backlog requests can undertake more requests and vice versa, allocate fewer requests. In this way, the overall stability of the upstream nodes is ensured, and requests are reasonably allocated to each node to avoid slow response or even downtime due to excessive node load.

## EWMA

The exponential moving average algorithm will choose the node with the least delay to load. The exponential moving average is based on the [EWMA](https://en.wikipedia.org/wiki/EWMA_chart) formula, using a sliding window to calculate the EWMA function value of a node within the window time as the predicted value of the request delay.

### Scenes

In latency-sensitive scenarios, the EWMA load balancing strategy is the most appropriate choice.

- When network jitter occurs, the delay is large, and the EWMA algorithm can dynamically adjust the window time to quickly perceive the existence of jitter, and the EWMA function value is close to the real value of network jitter;
- When the network is stable and the delay is small, the EWMA algorithm can dynamically increase the window time, and the EWMA function value returns to the normal level smoothly.

### Feature

APISIX uses P2C to optimize the EWMA load balancing strategy. The P2C method will randomly select two nodes, and then select the node with the lowest EWMA function value to achieve a local optimal solution.

## Backup Node

APISIX supports the configuration of standby nodes. When configuring a node, you can configure its priority property. APISIX will use lower-priority nodes only if all higher-priority nodes are unavailable.

Since the default priority of a node is `0`, we can configure a node with a negative priority as a backup node.

### Example

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": [
            {"host": "127.0.0.1", "port": 8081, "weight": 2000},
            {"host": "127.0.0.1", "port": 8082, "weight": 1, "priority": -1}
        ],
        ……
    }
}
```

As shown above, `127.0.0.1:8081` will only be used when the `127.0.0.1:8081` node is unavailable.

## Example

The following example shows how to use the APISIX consistent hashing algorithm. Create a route and configure it as follows. The configured `key` is `remote_addr`, which is the client IP. It is possible to observe whether requests are proxied to different upstream nodes when the client IP is always the same.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/index.html",
    "upstream":{
        "nodes":{
            "127.0.0.1:8081":1,
            "127.0.0.1:8082":1,
            "127.0.0.1:8083":1
        },
        "key": "remote_addr",
        "type":"chash"
    }
}'
```

The above code indicates that the load balancing policy of this route is `"type":"chash"`, and the key is `"key": "remote_addr"`. For more details, please refer to [Admin API](../admin-api.md#upstream).

Use the following command to request `12` times:

```shell
curl 127.0.0.1:9080/index.html
```

The result is as follows:

```shell
8083,8083,8083,8083,8083,8083,8083,8083,8083,8083,8083,8083
```
