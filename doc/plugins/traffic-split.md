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

- [中文](../zh-cn/plugins/traffic-split.md)

# Summary
  - [**Name**](#name)
  - [**Attributes**](#attributes)
  - [**How To Enable**](#how-to-enable)
    - [**Grayscale Release**](#grayscale-release)
    - [**Blue-green Release**](#blue-green-release)
    - [**Custom Release**](#custom-release)
  - [**Test Plugin**](#test-plugin)
    - [**Grayscale Test**](#grayscale-test)
    - [**Blue-green Test**](#blue-green-test)
    - [**Custom Test**](#custom-test)
  - [**Disable Plugin**](#disable-plugin)

## Name

The traffic splitting plug-in divides the request traffic according to a specified ratio and diverts it to the corresponding upstream. The plug-in can realize the functions of gray release, blue-green release and custom release.

## Attributes

| Name             | Type    | Requirement | Default | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------- | ------- | ---------------------------------------------------------------------------------------- |
| rules.match      | array[object]  | optional    |         |  | List of matching rules.                                                                    |
| rules.match.vars | array[array] | optional    |     |  | A list consisting of one or more {var, operator, val} elements, like this: {{var, operator, val}, {var, operator, val}, ...}}. For example: {"arg_name", "==", "json"}, which means that the current request parameter name is json. The var here is consistent with the naming of Nginx internal variables, so request_uri, host, etc. can also be used; for the operator part, the currently supported operators are ==, ~=, ~~, >, <, in, has and !. For specific usage of operators, please see the `operator-list` part of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |
| rules.upstreams  | array[object] | optional    |    |         | List of upstream configuration rules.                                                   |
| rules.upstreams.upstream_id  | string or integer | optional    |         |         | The upstream id is bound to the corresponding upstream(not currently supported).            |
| rules.upstreams.upstream   | object | optional    |     |      | Upstream configuration information.                                                    |
| rules.upstreams.upstream.type | enum | optional    | roundrobin  | [roundrobin, chash] | roundrobin supports weighted load, chash consistent hashing, the two are alternatives.   |
| rules.upstreams.upstream.nodes  | object | optional    |       |  | In the hash table, the key of the internal element is the list of upstream machine addresses, in the format of address + Port, where the address part can be an IP or a domain name, such as 192.168.1.100:80, foo.com:80, etc. value is the weight of the node. In particular, when the weight value is 0, it has special meaning, which usually means that the upstream node is invalid and never wants to be selected. |
| rules.upstreams.upstream.timeout  | object | optional    |  15     |   | Set the timeout period for connecting, sending and receiving messages (time unit: second, all default to 15 seconds).  |
| rules.upstreams.upstream.pass_host | enum | optional    | "pass"  | ["pass", "node", "rewrite"]  | pass: pass the host requested by the client, node: pass the host requested by the client; use the host configured with the upstream node, rewrite: rewrite the host with the value configured by the upstream_host. |
| rules.upstreams.upstream.name      | string | optional    |        |   | Identify the upstream service name, usage scenario, etc.  |
| rules.upstreams.upstream.upstream_host | string | optional    |    |   | Only valid when pass_host is configured as rewrite.    |
| rules.upstreams.weight | integer | optional    | weight = 1   |  | The traffic is divided according to the weight value, and the roundrobin algorithm is used to divide multiple weights. |

## How To Enable

### Grayscale Release

Traffic is split according to the weight value configured by upstreams in the plugin (the rule of `match` is not configured, and `match` is passed by default). The request traffic is divided into 4:2, 2/3 of the traffic reaches the upstream of the `1981` port in the plugin, and 1/3 of the traffic reaches the upstream of the default `1980` port on the route.

```json
{
    "weight": 2
}
```

There is only a `weight` value in the plugin upstreams, which represents the weight value of the upstream traffic arriving on the route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "upstreams": [
                        {
                            "upstream": {
                                "name": "upstream_A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":10
                                },
                                "timeout": {
                                    "connect": 15,
                                    "send": 15,
                                    "read": 15
                                }
                            },
                            "weight": 4
                        },
                        {
                            "weight": 2
                        }
                    ]
                }
            ]
        }
    },
    "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
    }
}'
```

### Blue-green Release

Get the blue and green conditions through the request header (you can also get through the request parameters or NGINX variables). After the `match` rule is matched, it means that all requests hit the upstream configured by the plugin, otherwise the request only hits the configuration on the route upstream.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "match": [
                        {
                            "vars": [
                                ["http_new-release","==","blue"]
                            ]
                        }
                    ],
                    "upstreams": [
                        {
                            "upstream": {
                                "name": "upstream_A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":10
                                }
                            }
                        }
                    ]
                }
            ]
        }
    },
    "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
    }
}'
```

### Custom Release

Multiple matching rules can be set in `match` (multiple conditions in `vars` are the relationship of `add`, and the relationship between multiple `vars` rules is the relationship of `or`; as long as one of the vars rules passes, it means `match` passed), only one is configured here, and the traffic is divided into 4:2 according to the value of `weight`. Among them, only the `weight` part represents the proportion of upstream on the route. When `match` fails to match, all traffic will only hit upstream on the route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "match": [
                        {
                            "vars": [
                                ["arg_name","==","jack"],
                                ["http_user-id",">","23"],
                                ["http_apisix-key","~~","[a-z]+"]
                            ]
                        }
                    ],
                    "upstreams": [
                        {
                            "upstream": {
                                "name": "upstream_A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":10
                                }
                            },
                            "weight": 4
                        },
                        {
                            "weight": 2
                        }
                    ]
                }
            ]
        }
    },
    "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
    }
}'
```

The plug-in sets the request matching rules and sets the port to upstream with `1981`, and the route has upstream with port `1980`.

## Test Plugin

### Grayscale Test

**2/3 of the requests hit the upstream on port 1981, and 1/3 of the traffic hit the upstream on port 1980.**

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980

$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

### Blue-green Test

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'new-release: blue' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

When the match is passed, all requests will hit the upstream configured by the plugin, otherwise hit the upstream configured on the route.

### Custom Test

**After the verification of the `match` rule passed, 2/3 of the requests hit the upstream of port 1981, and 1/3 hit the upstream of port 1980.**

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

The match check succeeds, but it hits the upstream of the default port of `1980`.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

The match check succeeds and it hits the upstream port of `1981`.

**The `match` rule verification failed (missing request header `apisix-key`), the response is the default upstream data `hello 1980`**

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

## Disable Plugin

When you want to remove the traffic-split plug-in, it's very simple, just delete the corresponding json configuration in the plug-in configuration, no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
