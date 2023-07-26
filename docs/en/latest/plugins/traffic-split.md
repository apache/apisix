---
title: traffic-split
keywords:
  - Apache APISIX
  - API Gateway
  - Traffic Split
  - Blue-green Deployment
  - Canary Deployment
description: This document contains information about the Apache APISIX traffic-split Plugin, you can use it to dynamically direct portions of traffic to various Upstream services.
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

The `traffic-split` Plugin can be used to dynamically direct portions of traffic to various Upstream services.

This is done by configuring `match`, which are custom rules for splitting traffic, and `weighted_upstreams` which is a set of Upstreams to direct traffic to.

When a request is matched based on the `match` attribute configuration, it will be directed to the Upstreams based on their configured `weights`. You can also omit using the `match` attribute and direct all traffic based on `weighted_upstreams`.

:::note

The traffic ratio between Upstream services may be less accurate since round robin algorithm is used to direct traffic (especially when the state is reset).

:::

## Attributes

| Name                           | Type           | Required | Default    | Valid values                | Description                                                                                                                                                                                                                                                                                                                                               |
|--------------------------------|----------------|----------|------------|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| rules.match                    | array[object]  | False    |            |                             | Rules to match for conditional traffic split. By default the list is empty and the traffic will be split unconditionally.                                                                                                                                                                                                                                 |
| rules.match.vars               | array[array]   | False    |            |                             | List of variables to match for filtering requests for conditional traffic split. It is in the format `{variable operator value}`. For example, `{"arg_name", "==", "json"}`. The variables here are consistent with NGINX internal variables. For details on supported operators, [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |
| rules.weighted_upstreams       | array[object]  | False    |            |                             | List of Upstream configurations.                                                                                                                                                                                                                                                                                                                          |
| weighted_upstreams.upstream_id | string/integer | False    |            |                             | ID of the configured Upstream object.                                                                                                                                                                                                                                                                                                                     |
| weighted_upstreams.upstream    | object         | False    |            |                             | Configuration of the Upstream.                                                                                                                                                                                                                                                                                                                            |
| upstream.type                  | enum           | False    | roundrobin | [roundrobin, chash]         | Type of mechanism to use for traffic splitting. `roundobin` supports weighted load and `chash` does consistent hashing.                                                                                                                                                                                                                                   |
| upstream.hash_on               | enum           | False    | vars       |                             | Only valid if the `type` is `chash`. Supported `vars` (Nginx variables), `header` (custom header), `cookie`, `consumer`, and `vars_combinations`. For more details, refer [Upstream](../admin-api.md#upstream).                                                                                                                                           |
| upstream.key                   | string         | False    |            |                             | Only valid if the `type` is `chash`. Finds the corresponding node `id` according to `hash_on` and `key` values. For more details, refer [Upstream](../admin-api.md#upstream).                                                                                                                                                                             |
| upstream.nodes                 | object         | False    |            |                             | IP addresses (with optional ports) of the Upstream nodes represented as a hash table. In the hash table, the key is the IP address and the value is the weight of the node. Setting `weight` to `0` means that a request is never forwarded to that node.                                                                                                 |
| upstream.timeout               | object         | False    | 15         |                             | Timeout in seconds for connecting, sending and receiving messages.                                                                                                                                                                                                                                                                                        |
| upstream.pass_host             | enum           | False    | "pass"     | ["pass", "node", "rewrite"] | Configures the host when the request is forwarded to the upstream. Can be one of `pass`, `node` or `rewrite`. `pass`- transparently passes the client's host to the Upstream. `node`- uses the host configured in the node of the Upstream. `rewrite`- Uses the value configured in `upstream_host`.                                                      |
| upstream.name                  | string         | False    |            |                             | Identifier for the Upstream for specifying service name, usage scenarios etc.                                                                                                                                                                                                                                                                             |
| upstream.upstream_host         | string         | False    |            |                             | Host of the Upstream request. Only valid when `pass_host` attribute is set to `rewrite`.                                                                                                                                                                                                                                                                  |
| weighted_upstreams.weight      | integer        | False    | weight = 1 |                             | Weight to give to each Upstream node for splitting traffic.                                                                                                                                                                                                                                                                                               |

:::note

Some of the configuration fields supported in Upstream are not supported in weighted_upstreams.upstream. These fields are `service_name`, `discovery_type`, `checks`, `retries`, `retry_timeout`, `desc`, `scheme`, `labels`, `create_time`, and `update_time`.

As a workaround, you can create an Upstream object and configure it in `weighted_upstreams.upstream_id` to achieve these functionalities.

:::

:::info IMPORTANT

In the `match` attribute configuration, the expression in variable is related as AND whereas multiple variables are related by OR.

If only the `weight` attribute is configured, it corresponds to the weight of the Upstream service configured on the Route or Service. You can see this in action below.

:::

## Enable Plugin

You can configure the Plugin on a Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Alternatively, you can configure `upstream_id` if you have already configured an Upstream object:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

:::tip

Configure via `upstream_id` to reuse Upstream's health detection, retires, and other functions.

:::

:::note

You can use both `upstream` configuration and `upstream_id` configuration together.

:::

## Example usage

The examples below shows different use cases for using the `traffic-split` Plugin.

### Canary release

This is the process of gradually rolling out a release by splitting an increasing percentage of traffic to the new release until all traffic is directed to the new release.

To set this up, you can configure the `weight` attribute of your `weighted_upstreams` as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Here, the weights are in the ratio 3:2 which means that 60% of the traffic reaches the Upstream service running on `:1981` (Plugin's Upstream) and 40% reaches the service running on `:1980` which is the Route's Upstream service.

Now to test this configuration, if you make 5 requests, 3 will hit one service and 2 will hit the other:

```shell
curl http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

```shell
curl http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

### Blue-green release

In this setup, user traffic is shifted from the "green" (production) environment to the "blue" (staging) environment once the new changes have been tested and accepted within the blue environment.

To set this up, you can configure `match` rules based on the request headers as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Here, if the request comes with a `release` header with value `new_release` it is directed to the new Upstream.

Now if you send a request with `new_release` as the value for the `release` header, it will be directed to one Upstream and other requests will be directed to another Upstream.

```shell
curl http://127.0.0.1:9080/index.html -H 'release: new_release' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
curl http://127.0.0.1:9080/index.html -H 'release: old_release' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

### Custom release

You can also make custom releases by configuring rules and setting weights.

In the example below, only one `vars` rule is configured and the multiple expressions in the rule have an AND relationship. The weights are configured in 3:2 ratio and traffic not matching the `vars` will be redirected to the Upstream configured on the Route.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

After the rules are matched, 60% of the traffic hit the Upstream on port `1981` and 40% hit the one on `1980`.

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'apisix-key: hello' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

If the rule fails to match, then the request is directed to the service on `1980`:

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'apisix-key: hello' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

In the example below, multiple `vars` rules are configured and they have an OR relationship.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

In the example below, both the `vars` rules are matched. After the rules are matched, 60% of the traffic is directed to the service on `1981` and 40% to the service on `1980`:

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack&name2=rose' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack&name2=rose' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

In the example below, the second `vars` rule fail to match. But since it is an OR relationship, the rules are matched and traffic is directed as configured:

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

In the example below the required headers are missing and both the `vars` rules fail to match and the request is directed to the default Upstream of the Route (`1980`):

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

### Multiple rules to correspond to Upstream

You can achieve one-to-one correspondence between rules and Upstream by configuring multiple `rules`:

For example, when the request header `x-api-id` is equal to `1` it should be directed to Upstream on port `1981` and if it is equal to `2` it should be directed to Upstream on port `1982`. And in other cases, it should default to the Upstream on port `1980`. You can configure this as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Now, when the request header `x-api-id` is equal to `1`, it will hit the Upstream on `1981`:

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 1'
```

```shell
1981
```

If request header `x-api-id` is equal to `2`, it will hit the Upstream on `1982`:

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 2'
```

```shell
1982
```

If request header `x-api-id` is equal to `3`, the rules do not match, and it will hit the Upstream on `1980`:

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 3'
```

```shell
1980
```

## Delete Plugin

To remove the `traffic-split` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
