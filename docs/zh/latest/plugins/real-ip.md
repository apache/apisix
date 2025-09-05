---
title: real-ip
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Real IP
description: real-ip 插件允许 Apache APISIX 通过 HTTP 请求头或 HTTP 查询字符串中传递的 IP 地址设置客户端的真实 IP。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/real-ip" />
</head>

## 描述

`real-ip` 插件允许 APISIX 通过 HTTP 请求头或 HTTP 查询字符串中传递的 IP 地址设置客户端的真实 IP。当 APISIX 位于反向代理之后时，此功能尤其有用，因为在这种情况下，代理可能会被视为请求发起客户端。

该插件在功能上类似于 NGINX 的 [ngx_http_realip_module](https://nginx.org/en/docs/http/ngx_http_realip_module.html)，但提供了更多的灵活性。

## 属性

| 名称              | 类型          | 是否必需 | 默认值 | 有效值                     | 描述                                                                 |
|-------------------|---------------|----------|--------|----------------------------|----------------------------------------------------------------------|
| source            | string        | 是       |        |                            | 内置变量，例如 `http_x_forwarded_for` 或 `arg_realip`。变量值应为一个有效的 IP 地址，表示客户端的真实 IP 地址，可选地包含端口。 |
| trusted_addresses | array[string] | 否       |        | IPv4 或 IPv6 地址数组（接受 CIDR 表示法） | 已知会发送正确替代地址的可信地址。此配置设置 [`set_real_ip_from`](https://nginx.org/en/docs/http/ngx_http_realip_module.html#set_real_ip_from) 指令。 |
| recursive         | boolean       | 否       | false  |                            | 如果为 false，则将匹配可信地址之一的原始客户端地址替换为配置的 `source` 中发送的最后一个地址。<br />如果为 true，则将匹配可信地址之一的原始客户端地址替换为配置的 `source` 中发送的最后一个非可信地址。 |

:::note
只有发送自 `apisix.trusted_addresses` 配置（支持 IP 和 CIDR）地址的 `X-Forwarded-*` 头才会被信任，并传递给插件或上游。如果未配置 `apisix.trusted_addresses` 或 ip 不在配置地址范围内的，`X-Forwarded-*` 头将全部被可信值覆盖。
:::

:::note
如果 `source` 属性中设置的地址丢失或者无效，该插件将不会更改客户端地址。
:::

## 示例

以下示例展示了如何在不同场景中配置 `real-ip`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 从 URI 参数获取真实客户端地址

以下示例演示了如何使用 URI 参数更新客户端 IP 地址。

创建如下路由。您应配置 `source` 以使用 [APISIX 变量](https://apisix.apache.org/docs/apisix/apisix-variable/)或者 [NGINX 变量](https://nginx.org/en/docs/varindex.html)从 URL 参数 `realip` 获取值。使用 `response-rewrite` 插件设置响应头，以验证客户端 IP 和端口是否实际更新。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "arg_realip",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr",
          "remote_port": "$remote_port"
        }
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

向路由发送带有 URL 参数中的真实 IP 和端口的请求：

```shell
curl -i "http://127.0.0.1:9080/get?realip=1.2.3.4:9080"
```

您应看到响应包含以下头：

```text
remote-addr: 1.2.3.4
remote-port: 9080
```

### 从请求头获取真实客户端地址

以下示例展示了当 APISIX 位于反向代理（例如负载均衡器）之后时，如何设置真实客户端 IP，此时代理在 [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) 请求头中暴露了真实客户端 IP。

创建如下路由。您应配置 `source` 以使用 [APISIX 变量](https://apisix.apache.org/docs/apisix/apisix-variable/)或者 [NGINX 变量](https://nginx.org/en/docs/varindex.html)从请求头 `X-Forwarded-For` 获取值。使用 response-rewrite 插件设置响应头，以验证客户端 IP 是否实际更新。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "http_x_forwarded_for",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr"
        }
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
curl -i "http://127.0.0.1:9080/get"
```

您应看到响应包含以下头：

```text
remote-addr: 10.26.3.19
```

IP 地址应对应于请求发起客户端的 IP 地址。

### 在多个代理之后获取真实客户端地址

以下示例展示了当 APISIX 位于多个代理之后时，如何获取真实客户端 IP，此时 [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) 请求头包含了一系列代理 IP 地址。

创建如下路由。您应配置 `source` 以使用 [APISIX 变量](https://apisix.apache.org/docs/apisix/apisix-variable/)或者 [NGINX 变量](https://nginx.org/en/docs/varindex.html)从请求头 `X-Forwarded-For` 获取值。将 `recursive` 设置为 `true`，以便将匹配可信地址之一的原始客户端地址替换为配置的 `source` 中发送的最后一个非可信地址。然后，使用 `response-rewrite` 插件设置响应头，以验证客户端 IP 是否实际更新。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
  "id": "real-ip-route",
  "uri": "/get",
  "plugins": {
    "real-ip": {
      "source": "http_x_forwarded_for",
      "recursive": true,
      "trusted_addresses": ["192.128.0.0/16", "127.0.0.0/24"]
    },
    "response-rewrite": {
      "headers": {
        "remote_addr": "$remote_addr"
      }
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
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Forwarded-For: 127.0.0.2, 192.128.1.1, 127.0.0.1"
```

您应看到响应包含以下头：

```text
remote-addr: 127.0.0.2
```
