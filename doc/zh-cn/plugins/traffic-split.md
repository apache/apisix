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

- [English](../../plugins/traffic-split.md)

# 目录

- [名字](#名字)
- [属性](#属性)
- [如何启用](#如何启用)
- [示例](#示例)
  - [灰度发布](#灰度发布)
  - [蓝绿发布](#蓝绿发布)
  - [自定义发布](#自定义发布)
- [禁用插件](#禁用插件)

## 名字

traffic-split 插件使用户可以逐步引导各个上游之间的流量百分比。

注：由于加权循环算法（特别是在重置wrr状态时）的缺点，因此每个上游之间的比率可能不太准确。

## 属性

|              参数名             | 类型          | 可选项 | 默认值 | 有效值 | 描述                 |
| ---------------------- | --------------| ------ | ------ | ------ | -------------------- |
| rules.match                    | array[object] | 可选  |        |        | 匹配规则列表  |
| rules.match.vars               | array[array]  | 可选   |        |        | 由一个或多个{var, operator, val}元素组成的列表，类似这样：{{var, operator, val}, {var, operator, val}, ...}}。例如：{"arg_name", "==", "json"}，表示当前请求参数 name 是 json。这里的 var 与 Nginx 内部自身变量命名是保持一致，所以也可以使用 request_uri、host 等；对于 operator 部分，目前已支持的运算符有 ==、~=、~~、>、<、in、has 和 ! 。操作符的具体用法请看 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 `operator-list` 部分。 |
| rules.weighted_upstreams       | array[object] | 可选   |        |        | 上游配置规则列表。 |
| weighted_upstreams.upstream_id | string / integer | 可选   |        |        | 通过上游 id 绑定对应上游(暂不支持)。 |
| weighted_upstreams.upstream    | object | 可选   |        |        | 上游配置信息。 |
| upstream.type                  | enum   | 可选   |   roundrobin |  [roundrobin, chash]      | roundrobin 支持权重的负载，chash 一致性哈希，两者是二选一的(目前只支持 `roundrobin`)。 |
| upstream.nodes                 | object | 可选   |        |        | 哈希表，内部元素的 key 是上游机器地址 列表，格式为地址 + Port，其中地址部 分可以是 IP 也可以是域名，⽐如 192.168.1.100:80、foo.com:80等。 value 则是节点的权重，特别的，当权重 值为 0 有特殊含义，通常代表该上游节点 失效，永远不希望被选中。 |
| upstream.timeout               | object | 可选   |  15     |        | 设置连接、发送消息、接收消息的超时时间(时间单位：秒，都默认为 15 秒)。 |
| upstream.pass_host             | enum   | 可选   | "pass"   | ["pass", "node", "rewrite"]  | pass: 透传客户端请求的 host, node: 不透传客户端请求的 host; 使用 upstream node 配置的 host, rewrite: 使用 upstream_host 配置的值重写 host 。 |
| `upstream.name`                  | string | 可选   |        |  | 标识上游服务名称、使⽤场景等。 |
| upstream.upstream_host         | string | 可选   |        |        | 只在 pass_host 配置为 rewrite 时有效。 |
| weighted_upstreams.weight      | integer | 可选   |   weight = 1     |        | 根据 `weight` 值做流量划分，多个 weight 之间使用 roundrobin 算法划分。|

traffic-split 插件主要由 `match` 和 `weighted_upstreams` 两部分组成，`match` 是自定义的条件规则，`weighted_upstreams` 是 upstream 的配置信息。如果配置 `match` 和 `weighted_upstreams` 信息，那么在 `match` 规则校验通过后，会根据 `weighted_upstreams` 中的 `weight` 值；引导插件中各个 upstream 之间的流量比例，否则，所有流量直接到达 `route` 或 `service` 上配置的 `upstream`。当然你也可以只配置 `weighted_upstreams` 部分，这样会直接根据 `weighted_upstreams` 中的 `weight` 值，引导插件中各个 upstream 之间的流量比例。

>注：1、在 `match` 里，vars 中的表达式是 `and` 的关系，多个 `vars` 之间是 `or` 的关系。2、在插件的 weighted_upstreams 域中，如果存在只有 `weight` 的结构，表示 `route` 或 `service` 上的 upstream 流量权重值。例如：

```json
"weighted_upstreams": [
    ......
    {
        "weight": 2
    }
]
```

## 如何启用

创建一个路由并启用 `traffic-split` 插件：

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

## 示例

### 灰度发布

缺少 `match` 规则部分，根据插件中 `weighted_upstreams` 配置的 `weight` 值做流量分流。将 `插件的 upstream` 与 `route 的 upstream` 按 3:2 的流量比例进行划分，其中 60% 的流量到达插件中的 `1981` 端口的 upstream， 40% 的流量到达 route 上默认 `1980` 端口的 upstream。

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

**插件测试:**

请求5次，3次请求命中插件1981端口的 upstream, 2次请求命中 `route` 的1980端口 upstream。

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

### 蓝绿发布

通过请求头获取 `match` 规则参数(也可以通过请求参数获取或NGINX变量)，在 `match` 规则匹配通过后，表示所有请求都命中到插件配置的 upstream ，否则所以请求只命中 `route` 上配置的 upstream 。

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

**插件测试：**

`match` 规则匹配通过，所有请求都命中插件配置的1981端口 upstream ：

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'release: new_release' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

`match` 规则匹配失败，所有请求都命中 `route` 上配置的 1980端口 upstream ：

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'release: old_release' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

### 自定义发布

`match` 中可以设置多个 `vars` 规则，`vars` 中的多个表达式之间是 `add` 的关系， 多个 `vars` 规则之间是 `or` 的关系；只要其中一个 vars 规则通过，则整个 `match` 通过。

**示例1：只配置了一个 `vars` 规则， `vars` 中的多个表达式是 `add` 的关系。在 `weighted_upstreams` 中根据 `weight` 值将流量按 3:2 划分，其中只有 `weight` 值的部分表示 `route` 上的 upstream 所占的比例。 当 `match` 匹配不通过时，所有的流量只会命中 route 上的 upstream 。**

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

插件设置了请求的 `match` 规则及端口为`1981`的 upstream，route 上具有端口为`1980`的 upstream。

**插件测试：**

>1、在 `match` 规则校验通过后, 60% 的请求命中到插件的1981端口的 upstream, 40% 的请求命中到 `route` 的1980端口的 upstream。

match 规则校验成功， 命中端口为`1981`的 upstream。

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

world 1981
```

match 规则校验失败，，命中默认端口为`1980`的 upstream。

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -H 'apisix-key: hello' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

在请求5次后，3次命中 `1981` 端口的服务，2次命中 `1980` 端口的服务。

>2、`match` 规则校验失败(缺少请求头 `apisix-key` ), 响应都为默认 upstream 的数据 `hello 1980`。

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -H 'user-id:30' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

**示例2：配置多个 `vars` 规则， `vars` 中的多个表达式是 `add` 的关系， 多个 `vars` 之间是 `or` 的关系。根据 `weighted_upstreams` 中的 `weight` 值将流量按 3:2 划分，其中只有 `weight` 值的部分表示 route 上的 upstream 所占的比例。 当 `match` 匹配不通过时，所有的流量只会命中 route 上的 upstream 。**

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

插件设置了请求的 `match` 规则及端口为`1981`的 upstream，route 上具有端口为`1980`的 upstream 。

**测试插件：**

>1、两个 `vars` 的表达式匹配成功， `match` 规则校验通过后, 60% 的请求命中到插件的1981端口 upstream, 40% 的请求命中到 `route` 的1980端口upstream。

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

在请求5次后，3次命中 `1981` 端口的服务，2次命中 `1980` 端口的服务。

>2、第二个 `vars` 的表达式匹配失败（缺少 `name2` 请求参数），`match` 规则校验通过后, 60% 的请求命中到插件的1981端口 upstream, 40% 的请求流量命中到 `route` 的1980端口 upstream。

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

在请求5次后，3次命中 `1981` 端口的服务，2次命中 `1980` 端口的服务。

>3、两个 `vars` 的表达式校验失败（缺少 `name` 和 `name2` 请求参数），`match` 规则校验失败, 响应都为默认 `route` 的 upstream 数据 `hello 1980`。

```shell
$ curl 'http://127.0.0.1:9080/index.html?name=jack' -i
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
......

hello 1980
```

## 禁用插件

当你想去掉 traffic-split 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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
