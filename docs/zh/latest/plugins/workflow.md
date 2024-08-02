---
title: workflow
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - workflow
  - 流量控制
description: 本文介绍了关于 Apache APISIX `workflow` 插件的基本信息及使用方法，你可以基于此插件进行复杂的流量操作。
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

`workflow` 插件引入 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 来提供复杂的流量控制功能。

## 属性

| 名称          | 类型   | 必选项  | 默认值                    | 有效值                                                                                                                                            | 描述 |
| ------------- | ------ | ------ | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| rules.case | array[array] | 是 |  |                                                                                                                            | 由一个或多个{var, operator, val}元素组成的列表，类似这样：{{var, operator, val}, {var, operator, val}, ...}}。例如：{"arg_name", "==", "json"}，表示当前请求参数 name 是 json。这里的 var 与 NGINX 内部自身变量命名保持一致，所以也可以使用 request_uri、host 等；对于 operator 部分，目前已支持的运算符有 ==、~=、~~、>、<、in、has 和 ! 。关于操作符的具体用法请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 的 `operator-list` 部分。 |
| rules.actions | array[object] | 是    |                   |                                                                                                                | 当 `case` 成功匹配时要执行的 `actions`。目前，`actions` 中只支持一个元素。`actions` 的唯一元素的第一个子元素可以是 `return` 或 `limit-count`。 |

### `actions` 属性

#### return

| 名称          | 类型   | 必选项  | 默认值                    | 有效值  | 描述 |
| ------------- | ------ | ------ | ------------------------ | ----| ------------- |
| actions[1].return | string | 否     |                      |  | 直接返回到客户端。 |
| actions[1].[2].code | integer | 否 |  | | 返回给客户端的 HTTP 状态码。 |

#### limit-count

| 名称          | 类型   | 必选项  | 默认值                    | 有效值  | 描述 |
| ------------- | ------ | ------ | ------------------------ | ----| ------------- |
| actions[1].limit-count | string | 否 |  | | 执行 `limit-count` 插件的功能。 |
| actions[1].[2] | object | 否 |  | | `limit-count` 插件的配置。 |

:::note

在 `rules` 中，按照 `rules` 的数组下标顺序依次匹配 `case`，如果 `case` 匹配成功，则直接执行对应的 `actions`。

:::

## 启用插件

以下示例展示了如何在路由中启用 `workflow` 插件：

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
    "uri":"/hello/*",
    "plugins":{
        "workflow":{
            "rules":[
                {
                    "case":[
                        ["uri", "==", "/hello/rejected"]
                    ],
                    "actions":[
                        [
                            "return",
                            {"code": 403}
                        ]
                    ]
                },
                {
                    "case":[
                        ["uri", "==", "/hello/v2/appid"]
                    ],
                    "actions":[
                        [
                            "limit-count",
                            {
                                "count":2,
                                "time_window":60,
                                "rejected_code":429
                            }
                        ]
                    ]
                }
            ]
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```

如上，我们启用了 `workflow` 插件，如果请求与 `rules` 中的 `case` 匹配，则会执行对应的 `actions`。

**示例 1: 如果请求的 uri 是 `/hello/rejected`，则返回给客户端状态码 `403`**

```shell
curl http://127.0.0.1:9080/hello/rejected -i
HTTP/1.1 403 Forbidden
......

{"error_msg":"rejected by workflow"}
```

**示例 2: 如果请求的 uri 是 `/hello/v2/appid`，则执行 `limit-count` 插件，限制请求的数量为 2，时间窗口为 60 秒，如果超过限制数量，则返回给客户端状态码 `429`**

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 200 OK
```

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 200 OK
```

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 429 Too Many Requests
```

**示例 3: 如果请求不能被任何 `case` 匹配，则 `workflow` 不会执行任何操作**

```shell
curl http://127.0.0.1:0080/hello/fake -i
HTTP/1.1 200 OK
```

## Delete Plugin

当你需要禁用 `workflow` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri":"/hello/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
