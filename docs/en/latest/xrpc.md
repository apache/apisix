---
title: xRPC
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

## What is xRPC

APISIX supports proxy TCP protocols, but there are times when a pure TCP protocol proxy is not enough. It would be helpful if you had an application-specific proxy, such as Redis Proxy, Kafka Proxy, etc. In addition, some features must be coded and decoded for that protocol before they can be implemented.

Therefore, Apache APISIX implements an L4 protocol extension framework called xRPC that allows developers to customize application-specific protocols. Based on xRPC, developers can codec requests and responses through Lua code and then implement fault injection, log reporting, dynamic routing, and other functions based on understanding the protocol content.

Based on the xRPC framework, APISIX can provide a proxy implementation of several major application protocols. In addition, users can also support their own private TCP-based application protocols based on this framework, giving them precise granularity and higher-level 7-layer control similar to HTTP protocol proxies.

## How to use

Currently, the steps for users to use xRPC are relatively simple and can be handled quickly in just two steps.

1. First, enable the corresponding protocol in `conf/config.yaml`.

```yaml
xrpc:
  protocols:
    - name: redis
```

2. Then specify the protocol in the relevant `stream_routes`.

```json
{
    ...
    "protocol": {
        "name": "redis",
        "conf": {
            "faults": [
                { "delay": 5, "key": "bogus_key", "commands":["GET", "MGET"]}
            ]
        }
    }
}
```

The TCP connection that hits that `stream_route` is then handled according to that protocol.

## Configuration

| Name        | Type   | Required | Default | Description                                     |
|-------------|--------|----------|---------|-------------------------------------------------|
| name        | string | True     |         | the protocol name                               |
| conf        |        | False    |         | the application-specific protocol configuration |
| superior_id | ID     | False    |         | the ID of the superior stream route             |

## Scenarios

### Fault injection

Taking Redis protocol as an example, after decoding the RESP protocol of Redis, we can know the command and parameters of the current request and then get the corresponding content according to the configuration, encode it using RESP protocol, and return it to the client.

Suppose the user uses the following routing configuration.

```json
{
    ...
    "protocol": {
        "name": "redis",
        "conf": {
            "faults": [
                { "delay": 5, "key": "bogus_key", "commands":["GET", "MGET"]}
            ]
        }
    }
}
```

Then when the command is "GET" or "MGET", and the operation key contains "bogus_key", it will get "delay" according to the configuration: "5" parameter, and the corresponding operation will be performed with a delay of 5 seconds.

Since xRPC requires developers to codec the protocol when customizing it, the same operation can be applied to other protocols.

### Dynamic Routing

In the process of proxy RPC protocol, there are often different RPC calls that need to be forwarded to different upstream requirements. Therefore, the xRPC framework has built-in support for dynamic routing.

To solve this problem, the concept of superior and subordinate is used in xRPC routing, as shown in the following two examples.

```json
# /stream_routes/1
{
    "sni": "a.test.com",
    "protocol": {
        "name": "xx",
        "conf": {
            ...
        }
    },
    "upstream_id": "1"
}
```

```json
# /stream_routes/2
{
    "protocol": {
        "name": "xx",
        "superior_id": "1",
        "conf": {
            ...
        }
    },
    "upstream_id": "2"
}
```

One specifies the `superior_id`, whose corresponding value is the ID of another route; the other specifies that the route with the `superior_id` is a subordinate route, subordinate to the one with the `superior_id`. Only the superior route is involved in matching at the entry point. The subordinate route is then matched by the specific protocol when the request is decoded.

For example, for the Dubbo RPC protocol, the subordinate route is matched based on the service_name and other parameters configured in the route and the actual service_name brought in the request. If the match is successful, the configuration above the subordinate route is used, otherwise, the configuration of the superior route is still used. In the above example, if the match for route 2 is successful, it will be forwarded to upstream 2; otherwise, it will still be forwarded to upstream 1.

### Log Reporting

xRPC supports logging-related functions. You can use this feature to filter requests that require attention, such as high latency, excessive transfer content, etc.

Each logger item configuration parameter will contain

- name: the Logger plugin name,
- filter: the prerequisites for the execution of the logger plugin(e.g., request processing time exceeding a given value),
- conf: the configuration of the logger plugin itself.

 The following configuration is an example:

```json
{
    ...
    "protocol": {
        "name": "redis",
        "logger": {
            {
                "name": "syslog",
                "filter": [
                    ["rpc_time", ">=", 0.01]
                ],
                "conf": {
                    "host": "127.0.0.1",
                    "port": 8125,
                }
            }
        }
    }
}
```

This configuration means that when the `rpc_time` is greater than 0.01 seconds, xRPC reports the request log to the log server via the `syslog` plugin. `conf` is the configuration of the logging server required by the `syslog` plugin.

Unlike standard TCP proxies, which only execute a logger when the connection is closed, xRPC executes a logger at the end of each 'request'.

The protocol itself defines the granularity of the specific request, and the xRPC extension code implements the request's granularity.

For example, in the Redis protocol, the execution of a command is considered a request.

### Dynamic metrics

xRPC also supports gathering metrics on the fly and exposing them via Prometheus.

To know how to enable Prometheus metrics for TCP and collect them, please refer to [prometheus](./plugins/prometheus.md).

To get the protocol-specific metrics, you need to:

1. Make sure the Prometheus is enabled for TCP
2. Add the metric field to the specific route and ensure the `enable` is true:

```json
{
    ...
    "protocol": {
        "name": "redis",
        "metric": {
            "enable": true
        }
    }
}
```

Different protocols will have different metrics. Please refer to the `Metrics` section of their own documentation.

## How to write your own protocol

Assuming that your protocol is named `my_proto`, you need to create a directory that can be introduced by `require "apisix.stream.xrpc.protocols.my_proto"`.
Inside this directory you need to have two files, `init.lua`, which implements the methods required by the xRPC framework, and `schema.lua`, which implements the schema checks for the protocol configuration.

For a concrete implementation, you can refer to the existing protocols at:

* https://github.com/apache/apisix/tree/master/apisix/stream/xrpc/protocols
* https://github.com/apache/apisix/tree/master/t/xrpc/apisix/stream/xrpc/protocols

To know what methods are required to be implemented and how the xRPC framework works, please refer to:
https://github.com/apache/apisix/tree/master/apisix/stream/xrpc/runner.lua
