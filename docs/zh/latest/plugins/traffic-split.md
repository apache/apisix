---
title: traffic-split
keywords:
  - APISIX
  - API 网关
  - Traffic Split
  - 灰度发布
  - 蓝绿发布
description: traffic-split 插件根据条件和/或权重将流量引导至各种上游服务。它提供了一种动态灵活的方法来实施发布策略和管理流量。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/traffic-split" />
</head>

## 描述

`traffic-split` 插件根据条件和/或权重将流量引导至各种上游服务。它提供了一种动态且灵活的方法来实施发布策略和管理流量。

:::note 注意

由于该插件使用了加权循环算法（特别是在重置 `wrr` 状态时），因此在使用该插件时，可能会存在上游服务之间的流量比例不精准现象。

:::

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| ---------------------- | --------------| ------ | ------ | ------ |-------------------------------------------------------- -------------------------------------------------- -------------------------------------------------- -------------------------------------------------- --------------------------------------------------|
| rules.match | array[object] | 否 | | | 要执行的一对或多对匹配条件和操作的数组。 |
| rules.match | array[object] | 否 | | | 条件流量分割的匹配规则。 |
| rules.match.vars | array[array] | 否 | | | 以 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 形式包含一个或多个匹配条件的数组，用于有条件地执行插件。 |
| rules.weighted_upstreams | array[object] | 否 | | | 上游配置列表。 |
| rules.weighted_upstreams.upstream_id | 字符串/整数 | 否 | | | 配置的上游对象的 ID。 |
| rules.weighted_upstreams.weight | 整数 | 否 | weight = 1 | | 每个上游的权重。 |
| rules.weighted_upstreams.upstream | object | 否 | | | 上游配置。此处不支持某些上游配置选项。这些字段为 `service_name`、`discovery_type`、`checks`、`retries`、`retry_timeout`、`desc` 和 `labels`。作为解决方法，您可以创建一个上游对象并在 `upstream_id` 中配置它。|
| rules.weighted_upstreams.upstream.type | array | 否 | roundrobin | [roundrobin, chash] | 流量分割算法。`roundrobin` 用于加权循环，`chash` 用于一致性哈希。|
| rules.weighted_upstreams.upstream.hash_on | array | 否 | vars | | 当 `t​​ype` 为 `chash` 时使用。支持对 [NGINX 变量](https://nginx.org/en/docs/varindex.html)、headers、cookie、Consumer 或 [Nginx 变量](https://nginx.org/en/docs/varindex.html) 的组合进行哈希处理。 |
| rules.weighted_upstreams.upstream.key | string | 否 | | | 当 `t​​ype` 为 `chash` 时使用。当 `hash_on` 设置为 `header` 或 `cookie` 时，需要 `key`。当 `hash_on` 设置为 `consumer` 时，不需要 `key`，因为消费者名称将自动用作密钥。 |
| rules.weighted_upstreams.upstream.nodes | object | 否 | | | 上游节点的地址。 |
| rules.weighted_upstreams.upstream.timeout | object | 否 | 15 | | 连接、发送和接收消息的超时时间（秒）。 |
| rules.weighted_upstreams.upstream.pass_host | array | 否 | "pass" | ["pass", "node", "rewrite"] | 决定如何传递主机名的模式。`pass` 将客户端的主机名传递给上游。`node` 传递上游节点中配置的主机。`rewrite` 传递 `upstream_host` 中配置的值。|
| rules.weighted_upstreams.upstream.name | string | 否 | | | 用于指定服务名称、使用场景等的上游标识符。|
| rules.weighted_upstreams.upstream.upstream_host | string | 否 | | | 当 `pass_host` 为 `rewrite` 时使用。上游的主机名。|

## 示例

以下示例展示了使用 `traffic-split` 插件的不同用例。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 实现 Canary 发布

以下示例演示了如何使用此插件实现 Canary 发布。

Canary 发布是一种逐步部署，其中越来越多的流量被定向到新版本，从而实现受控和受监控的发布。此方法可确保在完全重定向所有流量之前，尽早识别和解决新版本中的任何潜在问题或错误。

创建路由并使用以下规则配置 `traffic-split` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
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
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

每个 Upstream 的流量比例由该 Upstream 的权重占所有 Upstream 总权重的比例决定，这里总权重计算为：3 + 2 = 5。

因此，60% 的流量要转发到 `httpbin.org`，另外 40% 的流量要转发到 `mock.api7.ai`。

向路由发送 10 个连续请求来验证：

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

您应该会看到类似以下内容的响应：

```text
httpbin.org: 6, mock.api7.ai: 4
```

相应地调整上游权重以完成金丝雀发布。

### 实现蓝绿部署

以下示例演示如何使用此插件实现蓝绿部署。

蓝绿部署是一种部署策略，涉及维护两个相同的环境：蓝色和绿色。蓝色环境指的是当前的生产部署，绿色环境指的是新的部署。一旦绿色环境经过测试可以投入生产，流量将被路由到绿色环境，使其成为新的生产部署。

创建路由并配置 `traffic-split` 插件，以便仅当请求包含标头 `release: new_release` 时才执行插件以重定向流量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
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
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
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
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

向路由发送一个带有 `release` 标头的请求：

```shell
curl "http://127.0.0.1:9080/headers" -H 'release: new_release'
```

您应该会看到类似以下内容的响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    ...
  }
}
```

向路由发送一个不带任何附加标头的请求：

```shell
curl "http://127.0.0.1:9080/headers"
```

您应该会看到类似以下内容的响应：

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    ...
  }
}
```

### 使用 APISIX 表达式定义 POST 请求的匹配条件

以下示例演示了如何在规则中使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)，在满足 POST 请求的某些条件时有条件地执行插件。

创建路由并使用以下规则配置 `traffic-split` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "methods": ["POST"],
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["post_arg_id", "==", "1"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
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
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

发送主体为 `id=1` 的 POST 请求：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'id=1'
```

您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "id": "1"
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "4",
    "Content-Type": "application/x-www-form-urlencoded",
    "Host": "httpbin.org",
    ...
  },
  ...
}
```

发送主体中不包含 `id=1` 的 POST 请求：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'random=string'
```

您应该看到请求已转发到 `mock.api7.ai`。

### 使用 APISIX 表达式定义 AND 匹配条件

以下示例演示了如何在规则中使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)，在满足多个条件时有条件地执行插件。

创建路由并配置 `traffic-split` 插件，以便仅在满足所有三个条件时重定向流量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
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
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
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
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

如果满足条件，则 60% 的流量应定向到 `httpbin.org`，另外 40% 的流量应定向到 `mock.api7.ai`。如果不满足条件，则所有流量都应定向到 `mock.api7.ai`。

发送 10 个满足所有条件的连续请求以验证：

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=jack" -H 'user-id: 30' -H 'apisix-key: helloapisix' -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

您应该会看到类似以下内容的响应：

```text
httpbin.org: 6, mock.api7.ai: 4
```

连续发送 10 个不满足条件的请求进行验证：

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=random" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

您应该会看到类似以下内容的响应：

```text
httpbin.org: 0, mock.api7.ai: 10
```

### 使用 APISIX 表达式定义或匹配条件

以下示例演示了如何在规则中使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)，在满足任一条件集时有条件地执行插件。

创建路由并配置 `traffic-split` 插件，以在满足任一配置条件集时重定向流量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
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
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
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
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

或者，您也可以使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 中的 OR 运算符来实现这些条件。

如果满足条件，则 60% 的流量应定向到 `httpbin.org`，其余 40% 应定向到 `mock.api7.ai`。如果不满足条件，则所有流量都应定向到 `mock.api7.ai`。

发送 10 个满足第二组条件的连续请求以验证：

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name2=rose" -H 'user-id:30' -H 'apisix-key2: helloapisix' -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

您应该会看到类似以下内容的响应：

```json
httpbin.org: 6, mock.api7.ai: 4
```

发送 10 个连续的不满足任何一组条件的请求来验证：

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=random" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

您应该会看到类似以下内容的响应：

```json
httpbin.org: 0, mock.api7.ai: 10
```

### 为不同的上游配置不同的规则

以下示例演示了如何在规则集和上游之间设置一对一映射。

创建一个路由并使用以下匹配规则配置 `traffic-split` 插件，以便在请求包含标头 `x-api-id: 1` 或 `x-api-id: 2` 时将流量重定向到相应的上游服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
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
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                },
                "weight": 1
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
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "mock.api7.ai:443":1
                  }
                },
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
        "postman-echo.com:443": 1
      },
      "scheme": "https",
      "pass_host": "node"
    }
  }'
```

发送带有标头 `x-api-id: 1` 的请求：

```shell
curl "http://127.0.0.1:9080/headers" -H 'x-api-id: 1'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    ...
  }
}
```

发送带有标头 `x-api-id: 2` 的请求：

```shell
curl "http://127.0.0.1:9080/headers" -H 'x-api-id: 2'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    ...
  }
}
```

发送不带任何附加标头的请求：

```shell
curl "http://127.0.0.1:9080/headers"
```

您应该会看到类似以下内容的响应：

```json
{
  "headers": {
    "accept": "*/*",
    "host": "postman-echo.com",
    ...
  }
}
```
