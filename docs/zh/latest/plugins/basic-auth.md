---
title: basic-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Basic Auth
  - basic-auth
description: basic-auth 插件为消费者添加了基本访问身份验证，以便消费者在访问上游资源之前进行身份验证。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/basic-auth" />
</head>

## 描述

`basic-auth` 插件为 [消费者](../terminology/consumer.md) 添加了 [基本访问身份验证](https://en.wikipedia.org/wiki/Basic_access_authentication)，以便消费者在访问上游资源之前进行身份验证。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Indentifier` 和其他消费者自定义标头（如果已配置）。上游服务将能够区分消费者并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

## 属性

Consumer/Credentials 端：

| 名称     | 类型   | 必选项 | 描述                                                                                           |
| -------- | ------ | -----| ----------------------------------------------------------------------------------------------- |
| username | string | 是   | Consumer 的用户名并且该用户名是唯一，如果多个 Consumer 使用了相同的 `username`，将会出现请求匹配异常。|
| password | string | 是   | 用户的密码。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。        |

注意：schema 中还定义了 `encrypt_fields = {"password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Route 端：

| 名称             | 类型     | 必选项 | 默认值  | 描述                                                            |
| ---------------- | ------- | ------ | ------ | --------------------------------------------------------------- |
| hide_credentials | boolean | 否     | false  | 该参数设置为 `true` 时，则不会将 Authorization 请求头传递给 Upstream。|
| anonymous_consumer | boolean | 否    | false | 匿名消费者名称。如果已配置，则允许匿名用户绕过身份验证。 |

## 示例

以下示例演示了如何在不同场景中使用 `basic-auth` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### 在路由上实现基本身份验证

以下示例演示如何在路由上实现基本身份验证。

创建消费者 `johndoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

创建一个带有 `basic-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
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
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "john-key",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/get"
}
```

#### 使用无效密钥进行验证

使用无效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:invalid-key
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid user authorization"}
```

#### 无需密钥即可验证

无需密钥即可发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Missing authorization in request"}
```

### 隐藏上游的身份验证信息

以下示例演示了如何通过配置 `hide_credentials` 来防止密钥被发送到上游服务。APISIX 默认情况下会将身份验证密钥转发到上游服务，这在某些情况下可能会导致安全风险，您应该考虑更新 `hide_credentials`。

创建消费者 `johndoe` ：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

#### 不隐藏凭据

使用 `basic-auth` 创建路由，并将 `hide_credentials` 配置为 `false`，这是默认配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "basic-auth-route",
  "uri": "/anything",
  "plugins": {
    "basic-auth": {
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
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
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
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc2195-22bd5f401b13480e63c498c6",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

请注意，凭证以 base64 编码格式对上游服务可见。

:::tip

您还可以使用 `Authorization` 标头在请求中传递 base64 编码的凭据，如下所示：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "Authorization: Basic am9obmRvZTpqb2huLWtleQ=="
```

:::

#### 隐藏凭据

将插件的 `hide_credentials` 更新为 `true`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/basic-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "basic-auth": {
      "hide_credentials": true
    }
  }
}'
```

发送带有有效密钥的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
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
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc21a7-4f6ac87946e25f325167d53a",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

请注意，上游服务不再可见这些凭据。

### 将消费者自定义 ID 添加到标头

以下示例演示了如何在 `Consumer-Custom-Id` 标头中将消费者自定义 ID 附加到经过身份验证的请求，该 ID 可用于根据需要实现其他逻辑。

创建带有自定义 ID 标签的消费者 `johndoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

创建一个带有 `basic-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

使用有效密钥向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该看到一个带有 `X-Consumer-Custom-Id` 的 `HTTP/1.1 200 OK` 响应，类似于以下内容：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
}
```

### 匿名消费者的速率限制

以下示例演示了如何为普通消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证，并且配额较少。

创建普通消费者 `johndoe` 并配置 `limit-count` 插件以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

为消费者 `johndoe` 创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

创建匿名用户 `anonymous`，并配置 `limit-count` 插件，以允许 30 秒内配额为 1：

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

创建一个路由并配置 `basic-auth` 插件来接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {
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

为了验证，请使用 `john` 的密钥发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -u johndoe:john-key -o /dev/null -s -w "%{http_code}\n") && \
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
