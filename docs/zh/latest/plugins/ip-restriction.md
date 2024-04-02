---
title: ip-restriction
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - IP restriction
  - ip-restriction
description: 本文介绍了 Apache APISIX ip-restriction 插件的基本信息及使用方法。
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

`ip-restriction` 插件可以通过将 IP 地址列入白名单或黑名单来限制对服务或路由的访问。

支持对单个 IP 地址、多个 IP 地址和类似 `10.10.10.0/24` 的 CIDR（无类别域间路由）范围的限制。

## 属性

| 参数名    | 类型          | 必选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| whitelist | array[string] | 否   |        |        | 加入白名单的 IP 地址或 CIDR 范围。 |
| blacklist | array[string] | 否   |        |        | 加入黑名单的 IP 地址或 CIDR 范围。 |
| message | string | 否   | "Your IP address is not allowed" | [1, 1024] | 在未允许的 IP 访问的情况下返回的信息。 |

:::note

`whitelist` 和 `blacklist` 属性无法同时在同一个服务或路由上使用，只能使用其中之一。

:::

## 启用插件

以下示例展示了如何在特定路由上启用 `ip-restriction` 插件，并配置 `whitelist` 属性：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.1",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

当使用白名单之外的 IP 访问时，默认返回 `{"message":"Your IP address is not allowed"}`。如果想使用自定义的 `message`，可以在插件配置中进行调整：

```json
"plugins": {
    "ip-restriction": {
        "whitelist": [
            "127.0.0.1",
            "113.74.26.106/24"
        ],
        "message": "Do you want to do something bad?"
    }
}
```

## 测试插件

启用插件后，使用 `curl` 命令访问 APISIX 实例地址：

```shell
curl http://127.0.0.1:9080/index.html -i
```

返回 `200` HTTP 状态码，代表访问成功：

```shell
HTTP/1.1 200 OK
...
```

再从 IP 地址 `127.0.0.2` 发出请求：

```shell
curl http://127.0.0.1:9080/index.html -i --interface 127.0.0.2
```

返回 `403` HTTP 状态码，代表访问被阻止：

```shell
HTTP/1.1 403 Forbidden
...
{"message":"Your IP address is not allowed"}
```

如果你需要更改白名单或黑名单的 IP 地址，你只需更新插件配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.2",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

## 删除插件

当你需要禁用 `ip-restriction` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
