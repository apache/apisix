---
title: traffic-split
keywords:
  - APISIX
  - API 网关
  - Traffic Split
  - 灰度发布
  - 蓝绿发布
description: 本文介绍了 Apache APISIX traffic-split 插件的相关操作，你可以使用此插件动态地将部分流量引导至各种上游服务。
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

`traffic-split` 插件可以通过配置 `match` 和 `weighted_upstreams` 属性，从而动态地将部分流量引导至各种上游服务。该插件可应用于灰度发布和蓝绿发布的场景。

`match` 属性是用于引导流量的自定义规则，`weighted_upstreams` 属性则用于引导流量的上游服务。当一个请求被 `match` 属性匹配时，它将根据配置的 `weights` 属性被引导至上游服务。你也可以不使用 `match` 属性，只根据 `weighted_upstreams` 属性来引导所有流量。

:::note 注意

由于该插件使用了加权循环算法（特别是在重置 `wrr` 状态时），因此在使用该插件时，可能会存在上游服务之间的流量比例不精准现象。

:::

## 属性

|            名称             | 类型          | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------- | --------------| ------ | ------ | ------ |------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| rules.match                    | array[object] | 否  |        |        | 匹配规则列表，默认为空且规则将被无条件执行。                                                                                                                                                                                                                                                                                                                                           |
| rules.match.vars               | array[array]  | 否   |        |        | 由一个或多个 `{var, operator, val}` 元素组成的列表，例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 NGINX 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等；对于已支持的运算符，具体用法请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 `operator-list` 部分。 |
| rules.weighted_upstreams       | array[object] | 否   |        |        | 上游配置规则列表。                                                                                                                                                                                                                                                                                                                                                        |
| weighted_upstreams.upstream_id | string/integer | 否   |        |        | 通过上游 `id` 绑定对应上游。                                                                                                                                                                                                                                                                                                                                                  |
| weighted_upstreams.upstream    | object | 否   |        |        | 上游配置信息。                                                                                                                                                                                                                                                                                                                                                          |
| upstream.type                  | enum   | 否   |   roundrobin |  [roundrobin, chash]      | 流量引导机制的类型；`roundrobin` 表示支持权重的负载，`chash` 表示使用一致性哈希。                                                                                                                                                                                                                                                                                                                           |
| upstream.hash_on               | enum   | 否   | vars | | 该属性仅当 `upstream.type` 是 `chash` 时有效。支持的类型有 `vars`（NGINX 内置变量），`header`（自定义 header），`cookie`，`consumer`，`vars_combinations`。更多信息请参考 [Upstream](../admin-api.md#upstream) 用法。                                                                                                                                                                                                  |
| upstream.key                   | string | 否   |      |    | 该属性仅当 `upstream.type` 是 `chash` 时有效。根据 `hash_on` 和 `key` 来查找对应的 Node `id`。更多信息请参考 [Upstream](../admin-api.md#upstream) 用法。                                                                                                                                                                                                                                    |
| upstream.nodes                 | object | 否   |        |        | 哈希表，键是上游节点的 IP 地址与可选端口的组合，值是节点的权重。将 `weight` 设置为 `0` 表示一个请求永远不会被转发到该节点。                                                                                                                                                                                                             |
| upstream.timeout               | object | 否   |  15     |        | 发送和接收消息的超时时间（单位为秒）。                                                                                                                                                                                                                                                                                                                           |
| upstream.pass_host             | enum   | 否   | "pass"   | ["pass", "node", "rewrite"]  | 当请求被转发到上游时配置 `host`。`pass` 代表将客户端的 `host` 透明传输给上游；`node` 代表使用 `upstream` Node 中配置的 `host`； `rewrite` 代表使用配置项 `upstream_host` 的值。                                                                                                                                                                                                                                                                |
| upstream.name                  | string | 否   |        |  | 标识上游服务名称、使用场景等。                                                                                                                                                                                                                                                                                                                                                  |
| upstream.upstream_host         | string | 否   |        |        | 上游服务请求的 `host`，仅当 `pass_host` 属性配置为 `rewrite` 时生效。                                                                                                                                                                                                                                                                                                                                    |
| weighted_upstreams.weight      | integer | 否   |   weight = 1     |        | 根据 `weight` 值做流量划分，多个 `weight` 之间使用 `roundrobin` 算法划分。                                                                                                                                                                                                                                                                                                               |

:::note 注意

目前 `weighted_upstreams.upstream` 的配置不支持 `service_name`、`discovery_type`、`checks`、`retries`、`retry_timeout`、`desc`、`labels`、`create_time` 和 `update_time` 等字段。如果你需要使用这些字段，可以在创建上游对象时指定这些字段，然后在该插件中配置 `weighted_upstreams.upstream_id` 属性即可。

:::

:::info 重要

在 `match` 属性中，变量中的表达式以 AND 方式关联，多个变量以 OR 方式关联。

如果你仅配置了 `weight` 属性，那么它将会使用该 Route 或 Service 中的上游服务的权重。

:::

## 启用插件

以下示例展示了如何在指定路由上启用 `traffic-split` 插件，并通过插件中的 `upstream` 属性配置上游信息：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
-H "X-API-KEY: $admin_key" -X PUT -d '
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

通过 `upstream_id` 方式来绑定已定义的上游，可以复用上游已存在的健康检查、重试等功能。

:::

:::note 注意

`weighted_upstreams` 属性支持同时使用 `upstream` 和 `upstream_id` 两种配置方式。

:::

## 测试插件

### 灰度发布

灰度发布（又名金丝雀发布）是指在已经上线与未上线服务之间，能够平滑过渡的一种发布方式。在其上可以进行 A/B 测试，即让一部分用户继续用产品特性 A，一部分用户开始用产品特性 B。如果用户对特性 B 没有什么反对意见，那么逐步扩大范围，把所有用户都迁移到特性 B 上面来。

以下示例展示了如何通过配置 `weighted_upstreams` 的 `weight` 属性来实现流量分流。按 3:2 的权重流量比例进行划分，其中 60% 的流量到达运行在 `1981` 端口上的上游服务，40% 的流量到达运行在 `1980` 端口上的上游服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

**测试**

在请求 5 次后，其中会有 3 次命中运行在 `1981` 端口的插件上游服务，2 次命中运行在 `1980` 端口的路由上游服务：

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

在蓝绿发布场景中，你需要维护两个环境，一旦新的变化在蓝色环境（staging）中被测试和接受，用户流量就会从绿色环境（production）转移到蓝色环境。

以下示例展示了如何基于请求头来配置 `match` 规则：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

**测试**

1. 通过 `curl` 命令发出请求，如果请求带有一个值为 `new_release` 的 release header，它就会被引导至在插件上配置的新的上游服务：

```shell
curl http://127.0.0.1:9080/index.html -H 'release: new_release' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

2. 否则请求会被引导至在路由上配置的另一个上游服务：

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

你也可以通过配置规则和权重来实现自定义发布。

**示例 1**

下面的示例只配置了一个 `vars` 规则，流量按 3:2 的权重比例进行划分，不匹配 `vars` 的流量将被重定向到在路由上配置的上游服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

1. 通过 `curl` 命令发出请求，在 `match` 规则校验通过后，将会有 60% 的请求被引导至插件 `1981` 端口的上游服务，40% 的请求被引导至路由 `1980` 端口的上游服务：

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'apisix-key: hello' -i
```

在请求 5 次后，其中会有 3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务：

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

2. 如果 `match` 规则校验失败（如缺少请求头 `apisix-key`）, 那么请求将被引导至路由的 `1980` 端口的上游服务：

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

下面的示例配置了多个 `vars` 规则，流量按 3:2 的权重比例进行划分，不匹配 `vars` 的流量将被重定向到在路由上配置的上游服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

**测试**

1. 通过 `curl` 命令发出请求，如果两个 `vars` 表达式均匹配成功，`match` 规则校验通过后，将会有 60% 的请求被引导至插件 `1981` 端口的上游服务，40% 的请求命中到路由的 `1980` 端口的上游服务：

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack&name2=rose' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

在请求 5 次后，其中会有 3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务：

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

2. 如果第二个 `vars` 的表达式匹配失败（例如缺少 `name2` 请求参数），`match` 规则校验通过后，效果将会与上一种相同。即有 60% 的请求被引导至插件 `1981` 端口的上游服务，40% 的请求命中到路由的 `1980` 端口的上游服务：

```shell
curl 'http://127.0.0.1:9080/index.html?name=jack' \
-H 'user-id:30' -H 'user-id2:22' -H 'apisix-key: hello' -H 'apisix-key2: world' -i
```

在请求 5 次后，其中会有 3 次命中 `1981` 端口的服务，2 次命中 `1980` 端口的服务：

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
world 1981
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
...
hello 1980
```

3. 如果两个 `vars` 的表达式均匹配失败（如缺少 `name` 和 `name2` 请求参数），`match` 规则会校验失败，请求将被引导至路由的 `1980` 端口的上游服务：

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

以下示例展示了如何配置多个 `rules` 属性，实现不同的匹配规则与上游一一对应。当请求头 `x-api-id` 为 `1` 时，请求会被引导至 `1981` 端口的上游服务；当 `x-api-id` 为 `2` 时，请求会被引导至 `1982` 端口的上游服务；否则请求会被引导至 `1980` 端口的上游服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

1. 通过 `curl` 命令发出请求，请求头 `x-api-id` 为 `1`，则会命中 `1980` 端口的服务：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 1'
```

```shell
1981
```

2. 如果请求头 `x-api-id` 为 `2`，则会命中 `1982` 端口的服务：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 2'
```

```shell
1982
```

3. 如果请求头 `x-api-id` 为 `3`，规则不匹配，则会命中带 `1980` 端口的服务：

```shell
curl http://127.0.0.1:9080/hello -H 'x-api-id: 3'
```

```shell
1980
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
