---
title: ip-restriction
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - IP restriction
  - ip-restriction
description: ip-restriction 插件支持通过配置 IP 地址白名单或黑名单来限制 IP 地址对上游资源的访问。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ip-restriction" />
</head>

## 描述

`ip-restriction` 插件支持通过配置 IP 地址白名单或黑名单来限制 IP 地址对上游资源的访问。限制 IP 对资源的访问有助于防止未经授权的访问并加强 API 安全性。

## 属性

| 参数名    | 类型          | 必选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| whitelist | array[string] | 否   |        |        | 要列入白名单的 IP 列表。支持 IPv4、IPv6 和 CIDR 表示法。 |
| blacklist | array[string] | 否   |        |        | 要列入黑名单的 IP 列表。支持 IPv4、IPv6 和 CIDR 表示法。 |
| message | string | 否   | "Your IP address is not allowed" | [1, 1024] | 在未允许的 IP 访问的情况下返回的信息。 |

:::note

`whitelist` 或 `blacklist` 至少配置一个，但不能同时配置。

:::

## 示例

以下示例演示了如何针对不同场景配置 `ip-restriction` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 通过白名单限制访问

以下示例演示了如何将有权访问上游资源的 IP 地址列表列入白名单，并自定义拒绝访问的错误消息。

使用 `ip-restriction` 插件创建路由，将一系列 IP 列入白名单，并自定义拒绝访问时的错误消息：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.0.1/24"
        ],
        "message": "Access denied"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

如果您的 IP 被允许，您应该会收到 `HTTP/1.1 200 OK` 响应。如果不允许，您应该会收到 `HTTP/1.1 403 Forbidden` 响应，并显示以下错误消息：

```text
{"message":"Access denied"}
```

### 使用修改后的 IP 限制访问

以下示例演示了如何使用 `real-ip` 插件修改用于 IP 限制的 IP。如果 APISIX 位于反向代理之后，并且 APISIX 无法获得真实客户端 IP，则此功能特别有用。

使用 `ip-restriction` 插件创建路由，将特定 IP 地址列入白名单，并从 URL 参数 `realip` 获取客户端 IP 地址：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.1.241"
        ]
      },
      "real-ip": {
        "source": "arg_realip"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
      "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.1.241"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

使用不同的 IP 地址发送另一个请求：

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.10.24"
```

您应该会收到 `HTTP/1.1 403 Forbidden` 响应。
