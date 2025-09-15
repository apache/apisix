---
title: chaitin-waf
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - WAF
description: chaitin-waf 插件与长亭雷池 WAF 集成，以检测和阻止网络威胁，加强 API 安全性并保护用户数据。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/chaitin-waf" />
</head>

## 描述

`chaitin-waf` 插件与长亭雷池 WAF 集成服务集成，提供对基于 Web 的威胁的高级检测和预防，增强应用程序安全性并保护敏感的用户数据。

## 响应头

该插件可以添加以下响应头，具体取决于 `append_waf_resp_header` 和 `append_waf_debug_header` 的配置：

| 响应头 | 描述 |
|--------|-------------|
| `X-APISIX-CHAITIN-WAF` | 表示 APISIX 是否将请求转发到 WAF 服务器。<br />• `yes`: 请求已转发到 WAF 服务器。<br />• `no`: 请求未转发到 WAF 服务器。<br />• `unhealthy`: 请求匹配到配置的规则，但没有可用的 WAF 服务。<br />• `err`: 插件执行过程中发生错误，同时会包含 `X-APISIX-CHAITIN-WAF-ERROR` 响应头，提供错误详情。<br />• `waf-err`: 与 WAF 服务器交互时发生错误，同时会包含 `X-APISIX-CHAITIN-WAF-ERROR` 响应头，提供错误详情。<br />• `timeout`: 向 WAF 服务器的请求超时。 |
| `X-APISIX-CHAITIN-WAF-TIME` | 向 WAF 服务器请求的往返时间（RTT，单位为毫秒），包括网络延迟和 WAF 服务器处理时间。 |
| `X-APISIX-CHAITIN-WAF-STATUS` | WAF 服务器返回给 APISIX 的状态码。 |
| `X-APISIX-CHAITIN-WAF-ACTION` | WAF 服务器返回给 APISIX 的动作。<br />• `pass`: 请求被 WAF 服务允许。<br />• `reject`: 请求被 WAF 服务拦截。 |
| `X-APISIX-CHAITIN-WAF-ERROR` | 调试用响应头。包含 WAF 错误信息。 |
| `X-APISIX-CHAITIN-WAF-SERVER` | 调试用响应头。表示选用了哪个 WAF 服务器。 |

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|--------------------------|---------------------------|----------|---------|--------------|-------------|
| mode                     | string        | 否       | block   | `off`, `monitor`, `block`| 用于决定插件在匹配请求时的行为模式。在 `off` 模式下，跳过 WAF 检查。在 `monitor` 模式下，记录潜在威胁请求但不拦截。在 `block` 模式下，根据 WAF 服务的判断拦截存在威胁的请求。 |
| match                    | array[object] | 否       |         |                          | 匹配规则数组。插件使用这些规则来决定是否对请求执行 WAF 检查。如果列表为空，则处理所有请求。 |
| match.vars               | array[array]  | 否       |         |                          | 一个或多个匹配条件数组，使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 表达式来有条件地执行插件。 |
| append_waf_resp_header   | boolean       | 否       | true    |                          | 若为 true，则在响应中添加 `X-APISIX-CHAITIN-WAF`、`X-APISIX-CHAITIN-WAF-TIME`、`X-APISIX-CHAITIN-WAF-ACTION` 和 `X-APISIX-CHAITIN-WAF-STATUS` 响应头。 |
| append_waf_debug_header  | boolean       | 否       | false   |                          | 若为 true，则在响应中添加调试用响应头 `X-APISIX-CHAITIN-WAF-ERROR` 和 `X-APISIX-CHAITIN-WAF-SERVER`。仅当 `append_waf_resp_header` 为 true 时生效。 |
| config                   | object        | 否       |         |                          | 长亭 WAF 服务配置。这些配置在指定时会覆盖对应的元数据默认值。 |
| config.connect_timeout   | integer       | 否       | 1000    |                          | 与 WAF 服务的连接超时时间，单位为毫秒。 |
| config.send_timeout      | integer       | 否       | 1000    |                          | 向 WAF 服务发送数据的超时时间，单位为毫秒。 |
| config.read_timeout      | integer       | 否       | 1000    |                          | 从 WAF 服务读取数据的超时时间，单位为毫秒。 |
| config.req_body_size     | integer       | 否       | 1024    |                          | 允许的最大请求体大小，单位为 KB。 |
| config.keepalive_size    | integer       | 否       | 256     |                          | 可同时维持的与 WAF 检测服务的空闲连接数上限。 |
| config.keepalive_timeout | integer       | 否       | 60000   |                          | 与 WAF 服务的空闲连接超时时间，单位为毫秒。 |
| config.real_client_ip    | boolean       | 否       | true    |                          | 若为 true，则从 `X-Forwarded-For` 请求头中获取客户端 IP。若为 false，则插件使用连接中的客户端 IP。 |

## 插件元数据

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|--------------------------|---------------------------|----------|---------|--------------|-------------|
| nodes                    | array[object] | 是       |         |              | 长亭雷池 WAF 服务的地址数组。 |
| nodes.host               | string        | 是       |         |              | 长亭雷池 WAF 服务的地址，支持 IPv4、IPv6、Unix Socket 等。 |
| nodes.port               | integer       | 否       | 80      |              | 长亭雷池 WAF 服务的端口。 |
| mode                     | string        | 否       |         | block        | 用于决定插件在匹配请求时的行为模式。在 `off` 模式下，跳过 WAF 检查。在 `monitor` 模式下，记录潜在威胁请求但不拦截。在 `block` 模式下，根据 WAF 服务的判断拦截存在威胁的请求。 |
| config                   | object        | 否       |         |              | 长亭雷池 WAF 服务配置。 |
| config.connect_timeout   | integer       | 否       | 1000    |              | 与 WAF 服务的连接超时时间，单位为毫秒。 |
| config.send_timeout      | integer       | 否       | 1000    |              | 向 WAF 服务发送数据的超时时间，单位为毫秒。 |
| config.read_timeout      | integer       | 否       | 1000    |              | 从 WAF 服务读取数据的超时时间，单位为毫秒。 |
| config.req_body_size     | integer       | 否       | 1024    |              | 允许的最大请求体大小，单位为 KB。 |
| config.keepalive_size    | integer       | 否       | 256     |              | 可同时维持的与 WAF 检测服务的空闲连接数上限。 |
| config.keepalive_timeout | integer       | 否       | 60000   |              | 与 WAF 服务的空闲连接超时时间，单位为毫秒。 |
| config.real_client_ip    | boolean       | 否       | true    |              | 若为 true，则从 `X-Forwarded-For` 请求头中获取客户端 IP；若为 false，则插件使用连接中的客户端 IP。 |

## 示例

以下示例演示了如何针对不同场景配置 chaitin-waf 插件。

继续操作之前，请确保您已安装 [长亭雷池 WAF](https://docs.waf.chaitin.com/en/GetStarted/Deploy)。

:::note
只有发送自 `apisix.trusted_addresses` 配置（支持 IP 和 CIDR）地址的 `X-Forwarded-*` 头才会被信任，并传递给插件或上游。如果未配置 `apisix.trusted_addresses` 或 ip 不在配置地址范围内的，`X-Forwarded-*` 头将全部被可信值覆盖。
:::

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 拦截路由上的恶意请求

以下示例演示了如何与长亭雷池 WAF 集成，以保护路由上的流量，并立即拒绝恶意请求。

使用插件元数据配置长亭雷池 WAF 连接详细信息（相应地更新地址）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "nodes": [
      {
        "host": "172.22.222.5",
        "port": 8000
      }
    ]
  }'
```

创建路由并在路由上启用 `chaitin-waf` 以阻止被识别为恶意的请求：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {
        "mode": "block",
        "append_waf_resp_header": true,
        "append_waf_debug_header": true
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

向路由发送标准请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

向路由发送一个包含 SQL 注入的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

您应该会看到类似以下内容的 `HTTP/1.1 403 Forbidden` 响应：

```text
...
X-APISIX-CHAITIN-WAF-STATUS: 403
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF-SERVER: 172.22.222.5
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-TIME: 3
...

{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "276be6457d8447a4bf1f792501dfba6c"}
```

### 监控恶意请求

本示例演示如何与长亭雷池 WAF 集成，以监控所有使用 `chaitin-waf` 的路由（但不拒绝请求），并仅拒绝特定路由上的潜在恶意请求。

使用插件元数据配置长亭雷池 WAF 连接详细信息（相应地更新地址）并配置模式：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "nodes": [
      {
        "host": "172.22.222.5",
        "port": 8000
      }
    ],
    "mode": "monitor"
  }'
```

创建路由并启用 `chaitin-waf`，无需在路由上进行任何配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送标准请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

向路由发送一个包含 SQL 注入的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

您还应该收到 `HTTP/1.1 200 OK` 响应，因为请求在 `monitor` 模式下没有被阻止，但请在日志条目中观察以下内容：

```text
2025/09/09 11:44:08 [warn] 115#115: *31683 [lua] chaitin-waf.lua:385: do_access(): chaitin-waf monitor mode: request would have been rejected, event_id: 49bed20603e242f9be5ba6f1744bba4b, client: 172.20.0.1, server: _, request: "POST /anything HTTP/1.1", host: "127.0.0.1:9080"
```

如果你在路由上明确配置了 `mode`，它将优先于插件元数据中的配置。例如，如果你创建如下路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {
        "mode": "block"
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

向路由发送一个标准请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到一个 `HTTP/1.1 200 OK` 响应。

向路由发送一个包含 SQL 注入的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

您应该会看到一个类似以下内容的 `HTTP/1.1 403 Forbidden` 响应：

```text
...
X-APISIX-CHAITIN-WAF-STATUS: 403
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-TIME: 3
...

{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "c3eb25eaa7ae4c0d82eb8ceebf3600d0"}
```
