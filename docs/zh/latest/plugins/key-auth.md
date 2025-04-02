---
title: key-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Key Auth
  - key-auth
description: key-auth 插件支持使用身份验证密钥作为客户端在访问上游资源之前进行身份验证的机制。
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
    <link rel="canonical" href="https://docs.api7.ai/hub/key-auth" />
</head>

## 描述

`key-auth` 插件支持使用身份验证密钥作为客户端在访问上游资源之前进行身份验证的机制。

要使用该插件，您需要在 [Consumers](../terminology/consumer.md) 上配置身份验证密钥，并在路由或服务上启用该插件。密钥可以包含在请求 URL 查询字符串或请求标头中。然后，APISIX 将验证密钥以确定是否应允许或拒绝请求访问上游资源。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Indentifier` 和其他消费者自定义标头（如果已配置）。上游服务将能够区分消费者并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

## 属性

Consumer/Credential 端：

| 名称 | 类型   | 必选项  | 描述                                                                                                          |
| ---- | ------ | ------ | ------------------------------------------------------------------------------------------------------------- |
| key  | string | 是     | 不同的 Consumer 应有不同的 `key`，它应当是唯一的。如果多个 Consumer 使用了相同的 `key`，将会出现请求匹配异常。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。 |

注意：schema 中还定义了 `encrypt_fields = {"key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Route 端：

| 名称              | 类型   | 必选项 | 默认值 | 描述                                                                                                                                                       |
| ----------------- | ------ | ----- | ------ |----------------------------------------------------------------------------------------------------------------------------------------------------------|
| header            | string | 否    | apikey | 设置我们从哪个 header 获取 key。                                                                                                                                   |
| query             | string | 否    | apikey | 设置我们从哪个 query string 获取 key，优先级低于 `header`。                                                                                                              |
| hide_credentials  | boolean | 否    | false  | 如果为 `true`，则不要将含有认证信息的 header 或 query string 传递给 Upstream。  |

## 示例

以下示例演示了如何在不同场景中使用 `key-auth` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在路由上实现密钥认证

以下示例演示如何在路由上实现密钥认证并将密钥包含在请求标头中。

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

使用 `key-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

#### 使用有效密钥进行验证

使用有效密钥发送请求至：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: jack-key'
```

您应该收到 `HTTP/1.1 200 OK` 响应。

#### 使用无效密钥进行验证

使用无效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: wrong-key'
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid API key in request"}
```

#### 无需密钥即可验证

无需密钥即可发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Missing API key found in request"}
```

### 隐藏上游的身份验证信息

以下示例演示如何通过配置 `hide_credentials` 来防止密钥被发送到上游服务。默认情况下，身份验证密钥被转发到上游服务，这在某些情况下可能会导致安全风险。

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

#### 不隐藏凭据

使用 `key-auth` 创建路由，并将 `hide_credentials` 配置为 `false` (默认配置)：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "hide_credentials": false
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

发送带有有效密钥的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

您应该看到以下 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {
    "auth": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d8a5-2194962a67aa21dd33f94bb2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

注意凭证 `jack-key` 对于上游服务是可见的。

#### 隐藏凭据

将插件的 `hide_credentials` 更新为 `true`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/key-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "key-auth": {
      "hide_credentials": true
    }
  }
}'
```

发送带有有效密钥的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

您应该看到以下 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d85c-16f34dbb5629a5960183e803",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything"
}
```

注意凭证 `jack-key` 对上游服务不再可见。

### 演示标头和查询中的密钥优先级

以下示例演示了如何在路由上实现消费者的密钥身份验证，并自定义应包含密钥的 URL 参数。该示例还显示，当在标头和查询字符串中都配置了 API 密钥时，请求标头具有更高的优先级。

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

使用 `key-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "query": "auth"
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

#### 使用有效密钥进行验证

使用有效密钥发送请求至：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

#### 使用无效密钥进行验证

使用无效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid API key in request"}
```

#### 使用查询字符串中的有效密钥进行验证

但是，如果您在标头中包含有效密钥，而 URL 查询字符串中仍包含无效密钥：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key" -H 'apikey: jack-key'
```

您应该会看到 `HTTP/1.1 200 OK` 响应。这表明标头中包含的密钥始终具有更高的优先级。

### 将消费者自定义 ID 添加到标头

以下示例演示了如何在 `Consumer-Custom-Id` 标头中将消费者自定义 ID 附加到经过身份验证的请求，该 ID 可用于根据需要实现其他逻辑。

创建一个带有自定义 ID 标签的消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `key-auth` credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

To verify, send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {
    "auth": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

### 匿名消费者的速率限制

以下示例演示了如何为常规消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证，并且配额较少。

创建常规消费者 `jack` 并配置 `limit-count` 插件以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

为消费者 `jack` 创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

创建匿名用户 `anonymous`，并配置 `limit-count`插件，以允许 30 秒内配额为 1：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

创建路由并配置 `key-auth` 插件以接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {
        "anonymous_consumer": "anonymous"
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

为了验证，请使用 `jack` 的密钥发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jack-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 5 个请求中，3 个请求成功（状态代码 200），而其他请求被拒绝（状态代码 429）。

```text
200:    3, 429:    2
```

发送五个匿名请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，表明只有一个请求成功：

```text
200:    1, 429:    4
```
