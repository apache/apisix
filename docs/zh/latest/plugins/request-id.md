---
title: request-id
keywords:
  - APISIX
  - API 网关
  - Request ID
description: request-id 插件为通过 APISIX 代理的每个请求添加一个唯一的 ID，可用于跟踪 API 请求。
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

`request-id` 插件为每个通过 APISIX 代理的请求添加一个唯一 ID，可用于跟踪 API 请求。如果请求在 `header_name` 对应的 header 中带有 ID，则插件将使用 header 值作为唯一 ID，而不会用自动生成的 ID 进行覆盖。

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name | string | 否 | "X-Request-Id" | | 携带请求唯一 ID 的标头的名称。请注意，如果请求在 `header_name` 标头中携带 ID，则插件将使用标头值作为唯一 ID，并且不会用生成的 ID 覆盖它。|
| include_in_response | 布尔值 | 否 | true | | 如果为 true，则将生成的请求 ID 包含在响应标头中，其中标头的名称是 `header_name` 值。|
| algorithm | string | 否 | "uuid" | ["uuid","nanoid","range_id","ksuid"] | 用于生成唯一 ID 的算法。设置为 `uuid` 时，插件会生成一个通用唯一标识符。设置为 `nanoid` 时，插件会生成一个紧凑的、URL 安全的 ID。设置为 `range_id` 时，插件会生成具有特定参数的连续 ID。设置为 `ksuid` 时，插件会生成具有时间戳和随机值的连续 ID。|
| range_id | object | 否 | | |使用 `range_id` 算法生成请求 ID 的配置。|
| range_id.char_set | string | 否 | "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789" | 最小长度 6 | 用于 `range_id` 算法的字符集。|
| range_id.length | integer | 否 | 16 | >=6 | 用于 `range_id` 算法的生成的 ID 的长度。|

## 示例

以下示例演示了如何在不同场景中配置“request-id”。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 将请求 ID 附加到默认响应标头

以下示例演示了如何在路由上配置 `request-id`，如果请求中未传递标头值，则将生成的请求 ID 附加到默认的 `X-Request-Id` 响应标头。当在请求中设置 `X-Request-Id` 标头时，插件将把请求标头中的值作为请求 ID。

使用其默认配置（明确定义）创建带有 `request-id` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Request-Id",
        "include_in_response": true,
        "algorithm": "uuid"
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

您应该会收到一个 `HTTP/1.1 200 OK` 响应，并且会看到响应包含 `X-Request-Id` 标头和生成的 ID：

```text
X-Request-Id: b9b2c0d4-d058-46fa-bafc-dd91a0ccf441
```

使用标头中的自定义请求 ID 向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'X-Request-Id: some-custom-request-id'
```

您应该会收到 `HTTP/1.1 200 OK` 响应，并看到响应包含带有自定义请求 ID 的 `X-Request-Id` 标头：

```text
X-Request-Id：some-custom-request-id
```

### 将请求 ID 附加到自定义响应标头

以下示例演示如何在路由上配置 `request-id`，将生成的请求 ID 附加到指定的标头。

使用 `request-id` 插件创建路由，以定义带有请求 ID 的自定义标头，并将请求 ID 包含在响应标头中：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Req-Identifier",
        "include_in_response": true
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

您应该收到一个 `HTTP/1.1 200 OK` 响应，并看到响应包含带有生成 ID 的 `X-Req-Identifier` 标头：

```text
X-Req-Identifier：1c42ff59-ee4c-4103-a980-8359f4135b21
```

### 在响应标头中隐藏请求 ID

以下示例演示如何在路由上配置 `request-id`，将生成的请求 ID 附加到指定的标头。包含请求 ID 的标头应转发到上游服务，但不会在响应标头中返回。

使用 `request-id` 插件创建路由，以定义带有请求 ID 的自定义标头，而不在响应标头中包含请求 ID：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "X-Req-Identifier",
        "include_in_response": false
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

您应该收到 `HTTP/1.1 200 OK` 响应，并在响应标头中看到 `X-Req-Identifier` 标头。在响应主体中，您应该看到：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-6752748c-7d364f48564508db1e8c9ea8",
    "X-Forwarded-Host": "127.0.0.1",
    "X-Req-Identifier": "268092bc-15e1-4461-b277-bf7775f2856f"
  },
  ...
}
```

这表明请求 ID 已转发到上游服务，但未在响应标头中返回。

### 使用 `nanoid` 算法

以下示例演示如何在路由上配置 `request-id` 并使用 `nanoid` 算法生成请求 ID。

使用 `request-id` 插件创建路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "algorithm": "nanoid"
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

您应该收到一个 `HTTP/1.1 200 OK` 响应，并看到响应包含 `X-Req-Identifier` 标头，其中的 ID 使用 `nanoid` 算法生成：

```text
X-Request-Id: kepgHWCH2ycQ6JknQKrX2
```

### 使用 `ksuid` 算法

以下示例演示如何在路由上配置 `request-id` 并使用 `ksuid` 算法生成请求 ID。

使用 `request-id` 插件创建路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "algorithm": "ksuid"
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

您应该收到一个 `HTTP/1.1 200 OK` 响应，并看到响应包含 `X-Request-Id` 标头，其中的 ID 使用 `ksuid` 算法生成：

```text
X-Request-Id: 325ghCANEKjw6Jsfejg5p6QrLYB
```

如果装有[ksuid](https://github.com/segmentio/ksuid?tab=readme-ov-file#command-line-tool)命令工具，此 ID 可以通过`ksuid -f inspect 325ghCANEKjw6Jsfejg5p6QrLYB`查看：

``` text
REPRESENTATION:

    String: 325ghCANEKjw6Jsfejg5p6QrLYB
    Raw: 15430DBBD7F68AD7CA0AE277772AB36DDB1A3C13

COMPONENTS:

    Time: 2025-09-01 16:39:23 +0800 CST
    Timestamp: 356715963
    Payload: D7F68AD7CA0AE277772AB36DDB1A3C13
```

### 全局和在路由上附加请求 ID

以下示例演示如何将 `request-id` 配置为全局插件并在路由上附加两个 ID。

为 `request-id` 插件创建全局规则，将请求 ID 添加到自定义标头：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/global_rules" -X PUT -d '{
  "id": "rule-for-request-id",
  "plugins": {
    "request-id": {
      "header_name": "Global-Request-ID"
    }
  }
}'
```

使用 `request-id` 插件创建路由，将请求 ID 添加到不同的自定义标头：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "request-id-route",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "header_name": "Route-Request-ID"
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

您应该会收到 `HTTP/1.1 200 OK` 响应，并看到响应包含以下标头：

```text
Global-Request-ID：2e9b99c1-08ed-4a74-b347-49c0891b07ad
Route-Request-ID：d755666b-732c-4f0e-a30e-a7a71ace4e26
```
