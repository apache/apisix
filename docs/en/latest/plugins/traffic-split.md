---
title: traffic-split
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

## Summary

- [Name](#name)
- [Attributes](#attributes)
- [How To Enable](#how-to-enable)
- [Example](#example)
  - [Grayscale Release](#grayscale-release)
  - [Blue-green Release](#blue-green-release)
  - [Custom Release](#custom-release)
  - [Matching rules correspond to upstream](#matching-rules-correspond-to-upstream)
- [Disable Plugin](#disable-plugin)

## Name

The traffic split plugin allows users to incrementally direct percentages of traffic between various upstreams.

Note: The ratio between each upstream may not so accurate since the drawback of weighted round robin algorithm (especially when the wrr state is reset).

## Attributes

|               Name             |       Type    | Requirement | Default | Valid   | Description                                                                              |
| ------------------------------ | ------------- | ----------- | ------- | ------- | ---------------------------------------------------------------------------------------- |
| rules.match                    | array[object] | optional    |         |  | List of matching rules, by default the list is empty and the rule will be executed unconditionally. |
| rules.match.vars               | array[array]  | optional    |     |  | A list consisting of one or more {var, operator, val} elements, like this: {{var, operator, val}, {var, operator, val}, ...}}. For example: {"arg_name", "==", "json"}, which means that the current request parameter name is json. The var here is consistent with the naming of Nginx internal variables, so request_uri, host, etc. can also be used; for the operator part, the currently supported operators are ==, ~=, ~~, >, <, in, has and !. For specific usage of operators, please see the `operator-list` part of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |
| rules.weighted_upstreams       | array[object] | optional    |    |         | List of upstream configuration rules.                                                   |
| weighted_upstreams.upstream_id | string/integer| optional    |         |         | The upstream id is bound to the corresponding upstream.            |
| weighted_upstreams.upstream    | object        | optional    |     |      | Upstream configuration information.                                                    |
| upstream.type                  | enum          | optional    | roundrobin  | [roundrobin, chash] | roundrobin supports weighted load, chash consistent hashing, the two are alternatives.   |
| upstream.hash_on               | enum   | optional   | vars | | This option is only valid if the `type` is `chash`. Supported types `vars`(Nginx variables), `header`(custom header), `cookie`, `consumer`, `vars_combinations`, the default value is `vars`. For more details, please refer to [upstream](../admin-api.md#upstream) usage.|
| upstream.key                   | string | optional   |      |    | This option is only valid if the `type` is `chash`. Find the corresponding node `id` according to `hash_on` and `key`. For more details, please refer to [upstream](../admin-api.md#upstream) usage.|
| upstream.nodes                 | object        | optional    |       |  | In the hash table, the key of the internal element is the list of upstream machine addresses, in the format of address + Port, where the address part can be an IP or a domain name, such as 192.168.1.100:80, foo.com:80, etc. value is the weight of the node. In particular, when the weight value is 0, it has special meaning, which usually means that the upstream node is invalid and never wants to be selected. |
| upstream.timeout               | object        | optional    |  15     |   | Set the timeout period for connecting, sending and receiving messages (time unit: second, all default to 15 seconds).  |
| upstream.pass_host             | enum          | optional    | "pass"  | ["pass", "node", "rewrite"]  | `pass`: Pass the client's host transparently to the upstream; `node`: Use the host configured in the node of `upstream`; `rewrite`: Use the value of the configuration `upstream_host`. |
| upstream.name                | string        | optional    |        |   | Identify the upstream service name, usage scenario, etc.  |
| upstream.upstream_host         | string        | optional    |    |   | Only valid when pass_host is configured as rewrite.    |
| weighted_upstreams.weight      | integer       | optional    | weight = 1   |  | The traffic is divided according to the `weight` value, and the roundrobin algorithm is used to divide multiple `weight`. |

Currently, in the configuration of `weighted_upstreams.upstream`, the unsupported fields are:
service_name, discovery_type, checks, retries, retry_timeout, desc, scheme, labels, create_time and update_time. But you can use `weighted_upstreams.upstream_id` to bind the `upstream` object to achieve their functions.

The traffic-split plugin is mainly composed of two parts: `match` and `weighted_upstreams`. `match` is a custom conditional rule, and `weighted_upstreams` is upstream configuration information. If you configure `match` and `weighted_upstreams` information, then after the `match` rule is verified, it will be based on the `weight` value in `weighted_upstreams`; the ratio of traffic between each upstream in the plugin will be guided, otherwise, all traffic will be directly Reach the `upstream` configured on `route` or `service`. Of course, you can also configure only the `weighted_upstreams` part, which will directly guide the traffic ratio between each upstream in the plugin based on the `weight` value in `weighted_upstreams`.

Note: 1. In `match`, the expression in vars is the relationship of `and`, and the relationship between multiple `vars` is the relationship of `or`.  2. In the weighted_upstreams field of the plugin, if there is a structure with only `weight`, it means the upstream traffic weight value on `route` or `service`. Such as:

```json
"weighted_upstreams": [
    ......
    {
        "weight": 2
    }
]
```

## How To Enable

Create a route and enable the `traffic-split` plugin. When configuring the upstream information of the plugin, there are two ways:

1. Configure upstream information through the `upstream` attribute in the plugin.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "weighted_upstreams": [
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
                            "weight": 1
                        },
                        {
                            "weight": 1
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

2. Use the `upstream_id` attribute in the plugin to bind upstream.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "weighted_upstreams": [
                        {
                            "upstream_id": 1,
                            "weight": 1
                        },
                        {
                            "weight": 1
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

>Note: **1.** Use the `upstream_id` to bind the defined upstream, it can reuse upstream health detection, retry and other functions. **2.** Support the two configuration methods of `upstream` and `upstream_id` to be used together.

## Example

### Grayscale Release

The `match` rule part is missing, and the traffic is split according to the `weight` value configured by the `weighted_upstreams` in the plugin. Divide `plugin's upstream` and `route's upstream` according to the traffic ratio of 3:2, of which 60% of the traffic reaches the upstream of the `1981` port in the plugin, and 40% of the traffic reaches the default `1980` port on the route Upstream.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "weighted_upstreams": [
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
                            "weight": 3
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

**Test plugin:**

There are 5 requests, 3 requests hit the upstream of port 1981 of the plugin, and 2 requests hit the upstream of port 1980 of `route`.

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8

hello 1980

$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8

world 1981

......
```

### Blue-green Release

Get the `match` rule parameter through the request header (you can also get it through the request parameter or NGINX variable). After the `match` rule is matched, it means that all requests hit the upstream configured by the plugin, otherwise the request only hits the `route` configured upstream.

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
                                ["http_release","==","new_release"]
                            ]
                        }
                    ],
                    "weighted_upstreams": [
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

**Test plugin:**

The rule of `match` is matched, and all requests hit the upstream port 1981 configured by the plugin:

```shell
$ curl http://127.0.0.1:9080/index.html -H 'release: new_release' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

The `match` rule fails to match, and all requests hit the 1980 port upstream configured on the `route`:

```shell
$ curl http://127.0.0.1:9080/index.html -H 'release: old_release' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

### Custom Release

Multiple `vars` rules can be set in `match`. Multiple expressions in `vars` have an `add` relationship, and multiple `vars` rules have an `or` relationship; as long as one of the vars is required If the rule passes, the entire `match` passes.

**Example 1: Only one `vars` rule is configured, and multiple expressions in `vars` are in the relationship of `add`. In `weighted_upstreams`, the traffic is divided into 3:2 according to the value of `weight`, of which only the part of the `weight` value represents the proportion of upstream on the `route`. When `match` fails to pass, all traffic will only hit the upstream on the route.**

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
                    "weighted_upstreams": [
                        {
                            "upstream": {
                                "name": "upstream_A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":10
                                }
                            },
                            "weight": 3
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

The plugin sets the requested `match` rule and upstream with port `1981`, and the route has upstream with port `1980`.

**Test plugin:**

>1. After the verification of the `match` rule is passed, 60% of the requests hit the upstream of the plugin port 1981, and 40% of the requests hit the upstream of the 1980 port of the `route`.

The match rule is successfully verified, and the upstream port of `1981` is hit.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

The match rule fails to verify, and it hits the upstream of the default port of `1980`.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

After 5 requests, the service of port `1981` was hit 3 times, and the service of port `1980` was hit 2 times.

**Example 2: Configure multiple `vars` rules. Multiple expressions in `vars` are `add` relationships, and multiple `vars` are `or` relationships. According to the `weight` value in `weighted_upstreams`, the traffic is divided into 3:2, where only the part of the `weight` value represents the proportion of upstream on the route. When `match` fails to pass, all traffic will only hit the upstream on the route.**

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
                        },
                        {
                            "vars": [
                                ["arg_name2","==","rose"],
                                ["http_user-id2","!",">","33"],
                                ["http_apisix-key2","~~","[a-z]+"]
                            ]
                        }
                    ],
                    "weighted_upstreams": [
                        {
                            "upstream": {
                                "name": "upstream_A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":10
                                }
                            },
                            "weight": 3
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

The plugin sets the requested `match` rule and the upstream port of `1981`, and the route has upstream port of `1980`.

**Test plugin:**

>1. The expressions of the two `vars` are matched successfully. After the `match` rule is verified, 60% of the requests hit the 1981 port upstream of the plugin, and 40% of the requests hit the 1980 port upstream of the `route`.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack&name2=rose' -H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack&name2=rose' -H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

After 5 requests, the service of port `1981` was hit 3 times, and the service of port `1980` was hit 2 times.

>2. The second expression of `vars` failed to match (missing the `name2` request parameter). After the `match` rule was verified, 60% of the requests hit the plugin's 1981 port upstream, and 40% of the request traffic hits Go upstream to the 1980 port of `route`.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

After 5 requests, the service of port `1981` was hit 3 times, and the service of port `1980` was hit 2 times.

>3. The expression verification of two `vars` failed (missing the request parameters of `name` and `name2`), the `match` rule verification failed, and the response is the upstream data `hello 1980` of the default `route`.

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

### Matching rules correspond to upstream

By configuring multiple `rules`, we can achieve one-to-one correspondence between different matching rules and upstream.

**Example:**

When the request header `x-api-id` is equal to 1, it hits the upstream with port 1981; when `x-api-id` is equal to 2, it hits the upstream with port 1982; otherwise, it hits the upstream with port 1980 (the upstream response data is the corresponding port number).

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "traffic-split": {
            "rules": [
                {
                    "match": [
                        {
                            "vars": [
                                ["http_x-api-id","==","1"]
                            ]
                        }
                    ],
                    "weighted_upstreams": [
                        {
                            "upstream": {
                                "name": "upstream-A",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1981":1
                                }
                            },
                            "weight": 3
                        }
                    ]
                },
                {
                    "match": [
                        {
                            "vars": [
                                ["http_x-api-id","==","2"]
                            ]
                        }
                    ],
                    "weighted_upstreams": [
                        {
                            "upstream": {
                                "name": "upstream-B",
                                "type": "roundrobin",
                                "nodes": {
                                    "127.0.0.1:1982":1
                                }
                            },
                            "weight": 3
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

**Test plugin:**

The request header `x-api-id` is equal to 1, hitting the upstream with the 1981 port.

```shell
$ curl http://127.0.0.1:9080/hello -H 'x-api-id: 1'
1981
```

The request header `x-api-id` is equal to 2, hitting the upstream with the 1982 port.

```shell
$ curl http://127.0.0.1:9080/hello -H 'x-api-id: 2'
1982
```

The request header `x-api-id` is equal to 3, the rule does not match, and it hits the upstream with port 1980.

```shell
$ curl http://127.0.0.1:9080/hello -H 'x-api-id: 3'
1980
```

## Disable Plugin

When you want to remove the traffic-split plugin, it's very simple, just delete the corresponding json configuration in the plugin configuration, no need to restart the service, it will take effect immediately:

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
