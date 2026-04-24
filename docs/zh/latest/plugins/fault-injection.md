---
title: fault-injection
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Fault Injection
  - fault-injection
description: fault-injection 插件通过模拟受控故障或延迟来测试应用程序的弹性，非常适合混沌工程和故障条件分析场景。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/fault-injection" />
</head>

## 描述

`fault-injection` 插件通过模拟受控故障或延迟来测试应用程序的弹性。该插件在其他已配置插件之前执行，确保故障被一致性地应用。这使其非常适合混沌工程等场景，用于分析系统在故障条件下的行为。

该插件支持两种主要操作：

- `abort`：立即以指定的 HTTP 状态码（例如 `503 Service Unavailable`）终止请求，跳过所有后续插件。
- `delay`：在进一步处理请求之前引入指定的延迟。

:::info

`abort` 和 `delay` 至少需要配置其中一个。

:::

## 属性

| 名称              | 类型    | 必选项 | 有效值      | 描述                                                                                                                                                   |
|-------------------|---------|--------|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| abort             | object  | 否     |             | 终止请求并向客户端返回特定 HTTP 状态码的配置。`abort` 和 `delay` 至少需要配置其中一个。                                                              |
| abort.http_status | integer | 否     | [200, ...]  | 返回给客户端的 HTTP 状态码。配置 `abort` 时必填。                                                                                                     |
| abort.body        | string  | 否     |             | 返回给客户端的响应体。支持使用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)，例如 `client addr: $remote_addr\n`。            |
| abort.headers     | object  | 否     |             | 返回给客户端的响应头。标头值可包含 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)，例如 `$remote_addr`。                       |
| abort.percentage  | integer | 否     | [0, 100]    | 被终止的请求占比。若同时配置了 `vars`，则两个条件都必须满足。                                                                                         |
| abort.vars        | array[] | 否     |             | 终止请求前需匹配的规则。支持 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式，可通过 AND/OR 逻辑组合多个条件。                         |
| delay             | object  | 否     |             | 延迟请求的配置。`abort` 和 `delay` 至少需要配置其中一个。                                                                                             |
| delay.duration    | number  | 否     |             | 延迟时长（秒），可以为小数。配置 `delay` 时必填。                                                                                                     |
| delay.percentage  | integer | 否     | [0, 100]    | 被延迟的请求占比。若同时配置了 `vars`，则两个条件都必须满足。                                                                                         |
| delay.vars        | array[] | 否     |             | 延迟请求前需匹配的规则。支持 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式，可通过 AND/OR 逻辑组合多个条件。                         |

:::tip

`vars` 支持 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式，可灵活实现规则之间的 AND/OR 关系。示例：

```json
[
    [
        [ "arg_name","==","jack" ],
        [ "arg_age","==",18 ]
    ],
    [
        [ "arg_name2","==","allen" ]
    ]
]
```

以上示例中，前两个表达式之间是 AND 关系，而它们与第三个表达式之间是 OR 关系。

:::

## 示例

下面的示例演示了如何在不同场景中在路由上配置 `fault-injection`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 注入故障

以下示例演示如何在路由上配置 `fault-injection` 插件，拦截请求并以指定 HTTP 状态码响应，不转发请求到上游服务。

使用 `abort` 操作创建带有 `fault-injection` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "abort": {
          "http_status": 404,
          "body": "APISIX Fault Injection"
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
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 404 Not Found` 响应，并看到以下响应体，请求不会被转发到上游服务：

```text
APISIX Fault Injection
```

### 注入延迟

以下示例演示如何在路由上配置 `fault-injection` 插件以注入请求延迟。

使用 `delay` 操作创建带有 `fault-injection` 插件的路由，将响应延迟 3 秒：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "delay": {
          "duration": 3
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

向路由发送请求，并使用 `time` 计时：

```shell
time curl -i "http://127.0.0.1:9080/anything"
```

您应该收到来自上游服务的 `HTTP/1.1 200 OK` 响应，计时摘要应显示约 3 秒总耗时：

```text
real    0m3.034s
user    0m0.007s
sys     0m0.010s
```

### 条件注入故障

以下示例演示如何在路由上配置 `fault-injection` 插件，仅在满足特定请求条件时注入故障。

创建带有 `fault-injection` 插件的路由，配置仅当 URL 参数 `name` 等于 `john` 时才终止请求：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "abort": {
          "http_status": 404,
          "body": "APISIX Fault Injection",
          "headers": {
            "X-APISIX-Remote-Addr": "$remote_addr"
          },
          "vars": [
            [
              [ "arg_name","==","john" ]
            ]
          ]
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

发送 URL 参数 `name` 为 `john` 的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?name=john"
```

您应该收到类似以下的 `HTTP/1.1 404 Not Found` 响应：

```text
HTTP/1.1 404 Not Found
...
X-APISIX-Remote-Addr: 192.168.65.1

APISIX Fault Injection
```

发送 `name` 为其他值的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?name=jane"
```

您应该收到来自上游服务的 `HTTP/1.1 200 OK` 响应，没有注入故障。
