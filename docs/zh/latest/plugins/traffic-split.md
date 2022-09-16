---
title: traffic-split
keywords:
  - APISIX
  - API 网关
  - Traffic Split
description: 本文介绍了 Apache APISIX limit-conn 插件的相关操作，你可以使用此插件动态地将部分流量引导至各种上游服务。
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

`traffic-split` 插件可以通过配置 `match` 和 `weighted_upstreams` 属性，从而动态地将部分流量引导至各种上游服务。`match` 是用于分割流量的自定义规则，`weighted_upstreams` 是用于引导流量的一组上游服务。当一个请求被 `match` 属性匹配时，它将根据配置的 `weights` 属性被引导到上游服务。你也可以不使用 `match` 属性，而根据 `weighted_upstreams` 属性引导所有流量。

:::note 注意

由于使用了加权循环算法（特别是在重置 `wrr` 状态时），上游服务之间的流量比例可能不太准确。

:::

## 属性

|              参数名             | 类型          | 可选项 | 默认值 | 有效值 | 描述                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------- | --------------| ------ | ------ | ------ |------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| rules.match                    | array[object] | 否  |        |        | 匹配规则列表，默认为空且规则将被无条件执行。                                                                                                                                                                                                                                                                                                                                           |
| rules.match.vars               | array[array]  | 否   |        |        | 由一个或多个 `{var, operator, val}` 元素组成的列表，例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于 operator 部分，目前已支持的运算符有 `==`、`~=`、`~~`、`>`、`<`、`in`、`has` 和 `!` ，具体用法请看 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 `operator-list` 部分。 |
| rules.weighted_upstreams       | array[object] | 否   |        |        | 上游配置规则列表。                                                                                                                                                                                                                                                                                                                                                        |
| weighted_upstreams.upstream_id | string/integer | 否   |        |        | 通过上游 id 绑定对应上游。                                                                                                                                                                                                                                                                                                                                                  |
| weighted_upstreams.upstream    | object | 否   |        |        | 上游配置信息。                                                                                                                                                                                                                                                                                                                                                          |
| upstream.type                  | enum   | 否   |   roundrobin |  [roundrobin, chash]      | 流量分割机制的类型，`roundrobin` 支持权重的负载，`chash` 使用一致性哈希。                                                                                                                                                                                                                                                                                                                           |
| upstream.hash_on               | enum   | 否   | vars | | 该属性仅当 `upstream.type` 是 `chash` 时有效。支持的类型有 `vars`（NGINX 内置变量），`header`（自定义 header），`cookie`，`consumer`，`vars_combinations`。更多详细信息请参考 [Upstream](../admin-api.md#upstream) 用法。                                                                                                                                                                                                  |
| upstream.key                   | string | 否   |      |    | 该属性仅当 `upstream.type` 是 `chash` 时有效。根据 `hash_on` 和 `key` 来查找对应的 node `id`。更多详细信息请参考 [Upstream](../admin-api.md#upstream) 用法。                                                                                                                                                                                                                                    |
| upstream.nodes                 | object | 否   |        |        | 一个哈希表，键是上游节点的 IP 地址与可选端口的组合，值是节点的权重。将 `weight` 设置为 `0` 表示一个请求永远不会被转发到该节点。                                                                                                                                                                                                             |
| upstream.timeout               | object | 否   |  15     |        | 设置连接、发送消息、接收消息的超时时间（时间单位：秒，都默认为 15 秒）。                                                                                                                                                                                                                                                                                                                           |
| upstream.pass_host             | enum   | 否   | "pass"   | ["pass", "node", "rewrite"]  | 当请求被转发到上游时配置 `host`。`pass` 代表将客户端的 `host` 透明传输给上游；`node` 代表使用 `upstream` node 中配置的 `host`； `rewrite` 代表使用配置项 `upstream_host` 的值。                                                                                                                                                                                                                                                                |
| upstream.name                  | string | 否   |        |  | 标识上游服务名称、使⽤场景等。                                                                                                                                                                                                                                                                                                                                                  |
| upstream.upstream_host         | string | 否   |        |        | 上游服务请求的 `host`，仅当 `pass_host` 属性配置为 `rewrite` 时有效。                                                                                                                                                                                                                                                                                                                                    |
| weighted_upstreams.weight      | integer | 否   |   weight = 1     |        | 根据 `weight` 值做流量划分，多个 `weight` 之间使用 roundrobin 算法划分。                                                                                                                                                                                                                                                                                                               |

:::note 注意

目前在 `weighted_upstreams.upstream` 的配置中，尚不支持的字段有：`service_name`、`discovery_type`、`checks`、`retries`、`retry_timeout`、`desc`、`scheme`、`labels`、`create_time` 和 `update_time`。但是你可以创建一个 Upstream 对象，并在 `weighted_upstreams.upstream_id` 属性中配置以实现这些功能。

:::

:::info 重要

在 `match` 属性中，变量中的表达式以 AND 方式关联，而多个变量则以 OR 方式关联。

如果只配置了 `weight` 属性，那么它就对应于在 Route 或 Service 上配置的 Upstream 服务的权重。

:::

## 启用插件

以下示例展示了如何在指定路由上启用 `traffic-split` 插件，并通过插件中的 `upstream` 属性配置上游信息：

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

如果你已经配置了一个上游对象，你可以通过插件中的 `upstream_id` 属性来绑定上游服务：

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

:::tip 提示

通过 `upstream_id` 方式来绑定已定义的上游，可以复用上游具有的健康检测、重试等功能。

:::

:::note 注意

支持 `upstream` 和 `upstream_id` 的两种配置方式一起使用。

:::

## 测试插件

以下示例展示了使用 `traffic-split` 插件的不同用户案例。

### 灰度发布

灰度发布是逐步发布一个版本的过程，将越来越多的流量分给新版本，直到所有的流量都被引导到新版本。

以下示例展示了如何配置 `weighted_upstreams` 的 `weight` 属性：

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

缺少 `match` 规则部分，根据插件中 `weighted_upstreams` 配置的 `weight` 值做流量分流。将 `插件的 Upstream` 与 `路由的 Upstream` 按 3:2 的流量比例进行划分，其中 60% 的流量到达插件中的 `1981` 端口的 Upstream， 40% 的流量到达路由上默认 `1980` 端口的 Upstream。

**测试**

请求 5 次，3 次请求命中插件 `1981` 端口的 Upstream, 2 次请求命中路由的 `1980` 端口的 Upstream：

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

### 蓝绿发布

你需要维护两个环境，一旦新的变化在蓝色环境中被测试和接受，用户流量就会从绿色（生产）环境转移到蓝色（暂存）环境。

以下示例展示了如何基于请求头来配置 `match` 规则：

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

通过请求头获取 `match` 规则参数（也可以通过请求参数获取 NGINX 变量），在 `match` 规则匹配通过后，表示所有请求都命中到插件配置的 Upstream ，否则所有请求只命中路由上配置的 Upstream。

**测试**

通过 `curl` 命令请求访问 `new_release`，`match` 规则匹配通过，所有请求都命中插件配置的 `1981` 端口 Upstream：

```shell
curl http://127.0.0.1:9080/index.html -H 'release: new_release' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

通过 `curl` 命令请求访问 `old_release`，`match` 规则匹配失败，所有请求都命中路由上配置的 `1980` 端口 Upstream：

```shell
curl http://127.0.0.1:9080/index.html -H 'release: old_release' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

### 自定义发布

`match` 中可以设置多个 `vars` 规则，`vars` 中的多个表达式之间是 AND 的关系， 多个 `vars` 规则之间是 OR 的关系；只要其中一个 vars 规则通过，则整个 `match` 通过。

**示例 1**'

只配置了一个 `vars` 规则，在 `weighted_upstreams` 中根据 `weight` 值将流量按 3:2 划分，其中只有 `weight` 值的部分表示路由上的 Upstream 所占的比例。 当 `match` 匹配不通过时，所有的流量只会命中路由上的 Upstream。

插件设置了请求的 `match` 规则及端口为 `1981` 的 Upstream，路由上具有端口为 `1980` 的 Upstream：

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

**测试**

1. 在 `match` 规则校验通过后，60% 的请求命中到插件的 `1981` 端口的 Upstream, 40% 的请求命中到路由的 `1980` 端口的 Upstream。

`match` 规则校验成功，命中端口为 `1981` 的 Upstream：

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

`match` 规则校验失败，命中默认端口为 `1980` 的 Upstream：

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

在请求 5 次后，3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务。

2. `match` 规则校验失败（缺少请求头 `apisix-key`）, 响应都为默认 Upstream 的数据 `hello 1980`。

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

**示例 2**

配置多个 `vars` 规则，根据 `weighted_upstreams` 中的 `weight` 值将流量按 3:2 划分，其中只有 `weight` 值的部分表示路由上的 Upstream 所占的比例。 当 `match` 匹配不通过时，所有的流量只会命中路由上的 Upstream 。

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

插件设置了请求的 `match` 规则及端口为 `1981` 的 Upstream，路由上具有端口为 `1980` 的 Upstream 。

**测试**

1. 两个 `vars` 的表达式匹配成功，`match` 规则校验通过后，60% 的请求命中到插件的 `1981` 端口 Upstream, 40% 的请求命中到路由的 `1980` 端口 Upstream。

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

在请求 5 次后，3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务。

2. 第二个 `vars` 的表达式匹配失败（缺少 `name2` 请求参数），`match` 规则校验通过后，60% 的请求命中到插件的 `1981` 端口 Upstream, 40% 的请求流量命中到路由的 `1980` 端口 Upstream。

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

在请求 5 次后，3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务。

3. 两个 `vars` 的表达式校验失败（缺少 `name` 和 `name2` 请求参数），`match` 规则校验失败，响应都为默认路由的 Upstream 数据 `hello 1980`。

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

### 匹配规则与上游对应

通过配置多个 `rules`，我们可以实现不同的匹配规则与上游一一对应。

**示例**

当请求头 `x-api-id` 等于 1 时，命中 `1981` 端口的上游；当 `x-api-id` 等于 2 时，命中 `1982` 端口的上游；否则，命中 `1980` 端口的上游（上游响应数据为对应的端口号）。

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

**测试**

请求头 `x-api-id` 等于 1，命中带 `1981` 端口的上游：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 1'
```

```shell
1981
```

请求头 `x-api-id` 等于 2，命中带 `1982` 端口的上游：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 2'
```

```shell
1982
```

请求头 `x-api-id` 等于 3，规则不匹配，命中带 `1980` 端口的上游：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 3'
```

```shell
1980
```

## 禁用插件

当你需要禁用该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 \
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
