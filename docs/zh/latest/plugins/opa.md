---
title: opa
keywords:
  - Apache APISIX
  - API Gateway
  - 插件
  - Open Policy Agent
  - opa
description: 本文档包含有关 Apache APISIX opa 插件的信息。
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

`opa` 插件可用于与 [Open Policy Agent (OPA)](https://www.openpolicyagent.org) 集成。OPA 是一个策略引擎，帮助定义和执行授权策略，用以判断用户或应用程序是否拥有执行特定操作或访问特定资源的必要权限。将 OPA 与 APISIX 配合使用可以将授权逻辑从 APISIX 中解耦。

## 属性

| 名称              | 类型    | 是否必需 | 默认值   | 有效值        | 描述                                                                                                                                                                                   |
|-------------------|---------|----------|---------|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host              | string  | 是       |         |               | OPA 服务的主机地址。例如，`https://localhost:8181`。                                                                                                                                  |
| ssl_verify        | boolean | 否       | true    |               | 设置为 `true` 时验证 SSL 证书。                                                                                                                                                        |
| policy            | string  | 是       |         |               | OPA 策略路径。由 `package` 和 `decision` 组成。在使用自定义响应等高级功能时，可以省略 `decision`。                                                                                    |
| timeout           | integer | 否       | 3000ms  | [1, 60000]ms  | HTTP 调用的超时时间。                                                                                                                                                                   |
| keepalive         | boolean | 否       | true    |               | 设置为 `true` 时，为多个请求保持连接存活。                                                                                                                                                |
| keepalive_timeout | integer | 否       | 60000ms | [1000, ...]ms | 连接空闲后关闭的时间。                                                                                                                                                                  |
| keepalive_pool    | integer | 否       | 5       | [1, ...]ms    | 连接池限制。                                                                                                                                                                            |
| with_route        | boolean | 否       | false   |               | 设置为 `true` 时，发送当前路由的信息。                                                                                                                                                   |
| with_service      | boolean | 否       | false   |               | 设置为 `true` 时，发送当前服务的信息。                                                                                                                                                   |
| with_consumer     | boolean | 否       | false   |               | 设置为 `true` 时，发送当前消费者的信息。注意这可能会发送敏感信息，如 API 密钥。确保仅在确认安全时开启此项。                                                                              |
| with_body         | boolean | 否       | false   |               | 设置为 `true` 时，发送请求体。注意这可能会发送密码或 API 密钥等敏感信息。确保仅在理解安全隐患的情况下启用此功能。                                                                        |

## 数据定义

### APISIX 到 OPA 服务

以下 JSON 显示了 APISIX 发送给 OPA 服务的数据：

```json
{
    "type": "http",
    "request": {
        "scheme": "http",
        "path": "\/get",
        "headers": {
            "user-agent": "curl\/7.68.0",
            "accept": "*\/*",
            "host": "127.0.0.1:9080"
        },
        "query": {},
        "port": 9080,
        "method": "GET",
        "host": "127.0.0.1"
    },
    "var": {
        "timestamp": 1701234567,
        "server_addr": "127.0.0.1",
        "server_port": "9080",
        "remote_port": "port",
        "remote_addr": "ip address"
    },
    "route": {},
    "service": {},
    "consumer": {},
    "body": {}
}
```

以下是各个键的说明：

- `type` 表示请求类型（`http` 或 `stream`）.
- `request` 在 `type` 为 `http` 时使用，包含基本请求信息（URL、头信息等）.
- `var` 包含请求连接的基本信息（IP、端口、请求时间戳等）。
- `body` 包含请求的 HTTP 主体。
- `route`、`service` 和 `consumer` 包含 APISIX 中存储的相同数据，且仅在 `opa` 插件配置在这些对象上时发送。

### OPA 服务到 APISIX

以下 JSON 显示了 OPA 服务返回给 APISIX 的响应：

```json
{
    "result": {
        "allow": true,
        "reason": "test",
        "headers": {
            "an": "header"
        },
        "status_code": 401
    }
}
```

响应中的键说明：

- `allow` 是必需的，表示请求是否被允许通过 APISIX。
- `reason`、`headers` 和 `status_code` 是可选的，仅在配置自定义响应时返回。请参见下一节用例。

## 使用示例

首先，您需要启动 Open Policy Agent 环境：

```shell
docker run -d --name opa -p 8181:8181 openpolicyagent/opa:0.35.0 run -s
```

### 基本用法

当 OPA 服务运行后，您可以创建一个基本策略：

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/example1' \
    -H 'Content-Type: text/plain' \
    -d 'package example1

import input.request

default allow = false

allow {
    # HTTP method must GET
    request.method == "GET"
}'
```

然后，您可以在特定路由上配置 `opa` 插件：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/*",
    "plugins": {
        "opa": {
            "host": "http://127.0.0.1:8181",
            "policy": "example1"
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    }
}'
```

现在，测试一下：

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
```

如果请求不同的接口，请求会失败：

```shell
curl -i -X POST 127.0.0.1:9080/post
```

```shell
HTTP/1.1 403 FORBIDDEN
```

### 使用自定义响应

您也可以配置自定义响应来处理更复杂的场景：

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/example2' \
    -H 'Content-Type: text/plain' \
    -d 'package example2

import input.request

default allow = false

allow {
    request.method == "GET"
}

# custom response body (Accepts a string or an object, the object will respond as JSON format)
reason = "test" {
    not allow
}

# custom response header (The data of the object can be written in this way)
headers = {
    "Location": "http://example.com/auth"
} {
    not allow
}

# custom response status code
status_code = 302 {
    not allow
}'
```

将 `opa` 插件的策略参数更改为 `example2` 并测试：

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
```

如果请求失败，可以看到来自 OPA 服务的自定义响应：

```shell
curl -i -X POST 127.0.0.1:9080/post
```

```shell
HTTP/1.1 302 FOUND
Location: http://example.com/auth

test
```

### 发送 APISIX 数据

再看一个场景，当决策需要使用一些 APISIX 数据，比如 `route`、`consumer` 等时，如何操作？

如果您的 OPA 服务需要基于 APISIX 的路由和消费者等数据做决策，可以配置插件以发送这些数据。

下面示例是一个简单的 `echo` 策略，直接返回 APISIX 发送的数据：

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/echo' \
    -H 'Content-Type: text/plain' \
    -d 'package echo

allow = false
reason = input'
```

配置插件在路由上发送 APISIX 数据：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/*",
    "plugins": {
        "opa": {
            "host": "http://127.0.0.1:8181",
            "policy": "echo",
            "with_route": true
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    }
}'
```

请求时，可以通过自定义响应看到路由数据：

```shell
curl -X GET 127.0.0.1:9080/get
{
    "type": "http",
    "request": {
        xxx
    },
    "var": {
        xxx
    },
    "route": {
        xxx
    }
}
```

## 删除插件

若需删除 `opa` 插件，可从插件配置中删除对应的 JSON 配置。APISIX 会自动重新加载，无需重启。

您可以通过以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
