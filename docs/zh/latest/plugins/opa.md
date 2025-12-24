---
title: opa
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Open Policy Agent
  - opa
description: 本篇文档介绍了 Apache APISIX 通过 opa 插件与 Open Policy Agent 对接的相关信息。
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

`opa` 插件可用于与 [Open Policy Agent](https://www.openpolicyagent.org) 进行集成，实现后端服务的认证授权与访问服务等功能解耦，减少系统复杂性。

## 属性

| 名称              | 类型    | 必选项 | 默认值 | 有效值  | 描述                                                                                                                                                                                |
|-------------------|---------|----------|---------|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host              | string  | 是     |         |               | OPA 服务的主机地址，例如 `https://localhost:8181`。                                                                                                                   |
| ssl_verify        | boolean | 否    | true    |               | 当设置为 `true` 时，将验证 SSL 证书。                                                                                                                                          |
| policy            | string  | 是     |         |               | OPA 策略路径，是 `package` 和 `decision` 配置的组合。当使用高级功能（如自定义响应）时，你可以省略 `decision` 配置。指定命名空间时，请使用斜杠格式（例如 `examples/echo`），而不是点号格式（例如 `examples.echo`）。        |
| timeout           | integer | 否    | 3000ms  | [1, 60000]ms  | 设置 HTTP 调用超时时间。                                                                                                                                                                |
| keepalive         | boolean | 否    | true    |               | 当设置为 `true` 时，将为多个请求保持连接并处于活动状态。                                                                                                                               |
| keepalive_timeout | integer | 否    | 60000ms | [1000, ...]ms | 连接断开后的闲置时间。                                                                                                                                                                        |
| keepalive_pool    | integer | 否    | 5       | [1, ...]ms    | 连接池限制。                                                                                                                                                                    |
| with_route        | boolean | 否    | false   |               | 当设置为 `true` 时，发送关于当前 Route 的信息。                                                                                                                              |
| with_service      | boolean | 否    | false   |               | 当设置为 `true` 时，发送关于当前 Service 的信息。                                                                                                                            |
| with_consumer     | boolean | 否    | false   |               | 当设置为 `true` 时，发送关于当前 Consumer 的信息。注意，这可能会发送敏感信息，如 API key。请确保在安全的情况下才打开它。 |

## 数据定义

### APISIX 向 OPA 发送信息

下述示例代码展示了如何通过 APISIX 向 OPA 服务发送数据：

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
    "consumer": {}
}
```

上述代码具体释义如下：

- `type` 代表请求类型（如 `http` 或 `stream`）；
- `request` 则需要在 `type` 为 `http` 时使用，包含基本的请求信息（如 URL、头信息等）；
- `var` 包含关于请求连接的基本信息（如 IP、端口、请求时间戳等）；
- `route`、`service` 和 `consumer` 包含的数据与 APISIX 中存储的数据相同，只有当这些对象上配置了 `opa` 插件时才会发送。

### OPA 向 APISIX 返回数据

下述示例代码展示了 OPA 服务对 APISIX 发送请求后的响应数据：

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

上述响应中的代码释义如下：

- `allow` 配置是必不可少的，它表示请求是否允许通过 APISIX 进行转发；
- `reason`、`headers` 和 `status_code` 是可选的，只有当你配置一个自定义响应时才会返回这些选项信息，具体使用方法可查看后续测试用例。

## 测试插件

首先启动 OPA 环境：

```shell
docker run -d --name opa -p 8181:8181 openpolicyagent/opa:0.35.0 run -s
```

### 基本用法

一旦你运行了 OPA 服务，就可以进行基本策略的创建：

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

然后在指定路由上配置 `opa` 插件：

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

使用如下命令进行测试：

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
```

如果尝试向不同的端点发出请求，会出现请求失败的状态：

```shell
curl -i -X POST 127.0.0.1:9080/post
```

```shell
HTTP/1.1 403 FORBIDDEN
```

### 使用自定义响应

除了基础用法外，你还可以为更复杂的使用场景配置自定义响应，参考示例如下：

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

同时，你可以将 `opa` 插件的策略参数调整为 `example2`，然后发出请求进行测试：

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
```

此时如果你发出一个失败请求，将会收到来自 OPA 服务的自定义响应反馈，如下所示：

```shell
curl -i -X POST 127.0.0.1:9080/post
```

```shell
HTTP/1.1 302 FOUND
Location: http://example.com/auth

test
```

### 发送 APISIX 数据

如果你的 OPA 服务需要根据 APISIX 的某些数据（如 Route 和 Consumer 的详细信息）来进行后续操作时，则可以通过配置插件来实现。

下述示例展示了一个简单的 `echo` 策略，它将原样返回 APISIX 发送的数据：

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/echo' \
    -H 'Content-Type: text/plain' \
    -d 'package echo

allow = false
reason = input'
```

现在就可以在路由上配置插件来发送 APISIX 数据：

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

此时如果你提出一个请求，则可以通过自定义响应看到来自路由的数据：

```shell
curl -X GET 127.0.0.1:9080/get
```

```shell
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

当你需要禁用 `opa` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
