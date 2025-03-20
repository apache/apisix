---
title: hmac-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - HMAC Authentication
  - hmac-auth
description: hmac-auth 插件支持 HMAC 认证，保证请求的完整性，防止传输过程中的修改，增强 API 的安全性。
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

`hmac-auth` 插件支持 HMAC（基于哈希的消息认证码）认证，作为一种确保请求完整性的机制，防止它们在传输过程中被修改。要使用该插件，您需要在 [Consumers](../terminology/consumer.md) 上配置 HMAC 密钥，并在 Routes 或 Services 上启用该插件。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Indentifier` 和其他消费者自定义标头（如果已配置）。上游服务将能够区分消费者并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

启用后，插件会验证请求的 `Authorization` 标头中的 HMAC 签名，并检查传入的请求是否来自受信任的来源。具体来说，当 APISIX 收到 HMAC 签名的请求时，会从 `Authorization` 标头中提取密钥 ID。然后，APISIX 会检索相应的消费者配置，包括密钥。如果密钥 ID 有效且存在，APISIX 将使用请求的 `Date` 标头和密钥生成 HMAC 签名。如果生成的签名与 `Authorization` 标头中提供的签名匹配，则请求通过身份验证并转发到上游服务。

插件实现基于 [draft-cavage-http-signatures](https://www.ietf.org/archive/id/draft-cavage-http-signatures-12.txt)。

## 属性

以下属性可用于 Consumers 或 Credentials 的配置。

| 名称             | 类型          | 必选项 | 默认值        | 有效值                                      | 描述                                                                                                                                                                                      |
| ---------------- | ------------- | ------ | ------------- | ------------------------------------------| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| access_key       | string        | 是   |               |                                             |  消费者的唯一标识符，用于标识相关配置，例如密钥。                                                                                   |
| secret_key       | string        | 是   |               |                                             | 用于生成 HMAC 的密钥。此字段支持使用 [APISIX Secret](../terminology/secret.md) 资源将值保存在 Secret Manager 中。                       |

以下属性可用于 Routes 或 Services 的配置。

| 名称             | 类型          | 必选项 | 默认值        | 有效值                                      | 描述                                                                                                                                                                                      |
| ---------------- | ------------- | ------ | ------------- | ------------------------------------------| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| allowed_algorithms             | array[string]        | 否    | ["hmac-sha1", "hmac-sha256", "hmac-sha512"] | "hmac-sha1"、"hmac-sha256" 和 "hmac-sha512" 的组合 | 允许的 HMAC 算法列表。                                                                                                                                                                                |
| clock_skew            | integer       | 否    | 300             |                 >=1                          | 客户端请求的时间戳与 APISIX 服务器当前时间之间允许的最大时间差（以秒为单位）。这有助于解决客户端和服务器之间的时间同步差异，并防止重放攻击。时间戳将根据 Date 头中的时间（必须为 GMT 格式）进行计算。        |
| signed_headers        | array[string] | 否    |               |                                             | 客户端请求的 HMAC 签名中应包含的 HMAC 签名头列表。  |
| validate_request_body | boolean       | 否    | false         |                              | 如果为 true，则验证请求正文的完整性，以确保在传输过程中没有被篡改。具体来说，插件会创建一个 SHA-256 的 base64 编码 digest，并将其与 `Digest` 头进行比较。如果 `Digest` 头丢失或 digest 不匹配，验证将失败。                          |
| hide_credentials | boolean       | 否    | false         |                              | 如果为 true，则不会将授权请求头传递给上游服务。                        |
| anonymous_consumer | string    | 否    |          |                              | 匿名消费者名称。如果已配置，则允许匿名用户绕过身份验证。                        |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

## 示例

下面的示例说明了如何在不同场景中使用“hmac-auth”插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在路由上实现 HMAC 身份验证

以下示例演示如何在路由上实现 HMAC 身份验证。您还将在 `Consumer-Custom-Id` 标头中将消费者自定义 ID 附加到经过身份验证的请求，该 ID 可用于根据需要实现其他逻辑。

创建一个带有自定义 ID 标签的消费者 `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

为消费者创建 `hmac-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

使用 `hmac-auth` 插件的默认配置创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 06:41:29 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'}
```

使用生成的标头，向路由发送请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM=\"",
    "Date": "Fri, 06 Sep 2024 06:41:29 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### Hide Authorization Information From Upstream

As seen the in the [last example](#implement-hmac-authentication-on-a-route), the `Authorization` header passed to the Upstream includes the signature and all other details. This could potentially introduce security risks.

The following example demonstrates how to prevent these information from being sent to the Upstream service.

Update the plugin configuration to set `hide_credentials` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/hmac-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "hmac-auth": {
      "hide_credentials": true
    }
  }
}'
```

Send a request to the route:

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

You should see an `HTTP/1.1 200 OK` response and notice the `Authorization` header is entirely removed:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### Enable Body Validation

The following example demonstrates how to enable body validation to ensure the integrity of the request body.

Create a consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为消费者创建 `hmac-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

Create a Route with the `hmac-auth` plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/post",
    "methods": ["POST"],
    "plugins": {
      "hmac-auth": {
        "validate_request_body": true
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

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-digest-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                 # key id
secret_key = b"john-secret-key"     # secret key
request_method = "POST"             # HTTP method
request_path = "/post"              # Route URI
algorithm= "hmac-sha256"            # can use other algorithms in allowed_algorithms
body = '{"name": "world"}'          # example request body

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s).
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# create the SHA-256 digest of the request body and base64 encode it
body_digest = hashlib.sha256(body.encode('utf-8')).digest()
body_digest_base64 = base64.b64encode(body_digest).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Digest": f"SHA-256={body_digest_base64}",
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date",'
        f'signature="{signature_base64}"'
    )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-digest-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 09:16:16 GMT', 'Digest': 'SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="'}
```

使用生成的标头，向路由发送请求：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H "Digest: SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\"name\": \"world\"}": ""
  },
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE=\"",
    "Content-Length": "17",
    "Content-Type": "application/x-www-form-urlencoded",
    "Date": "Fri, 06 Sep 2024 09:16:16 GMT",
    "Digest": "SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d978c3-49f929ad5237da5340bbbeb4",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/post"
}
```

如果您发送的请求没有摘要或摘要无效：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H "Digest: SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

您应该看到一个 `HTTP/1.1 401 Unauthorized` 响应，其中包含以下消息：

```text
{"message":"client request can't be validated"}
```

### 强制签名标头

以下示例演示了如何强制在请求的 HMAC 签名中对某些标头进行签名。

创建消费者 `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为消费者创建 `hmac-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

使用 `hmac-auth` 插件创建路由，该插件要求 HMAC 签名中存在三个标头：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
        "signed_headers": ["date","x-custom-header-a","x-custom-header-b"]
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

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-req-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms
custom_header_a = "hello123"       # required custom header
custom_header_b = "world456"       # required custom header

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
    f"x-custom-header-a: {custom_header_a}\n"
    f"x-custom-header-b: {custom_header_b}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date x-custom-header-a x-custom-header-b",'
        f'signature="{signature_base64}"'
    ),
    "x-custom-header-a": custom_header_a,
    "x-custom-header-b": custom_header_b
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-req-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 09:58:49 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="', 'x-custom-header-a': 'hello123', 'x-custom-header-b': 'world456'}
```

使用生成的标头，向路由发送请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
     -H "Date: Fri, 06 Sep 2024 09:58:49 GMT" \
     -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="' \
     -H "x-custom-header-a: hello123" \
     -H "x-custom-header-b: world456"
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE=\"",
    "Date": "Fri, 06 Sep 2024 09:58:49 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d98196-64a58db25ece71c077999ecd",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Custom-Header-A": "hello123",
    "X-Custom-Header-B": "world456",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 103.97.2.206",
  "url": "http://127.0.0.1/get"
}
```

### 匿名消费者的速率限制

以下示例演示了如何为常规消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证，配额较少。

创建常规消费者 `john`，并配置 `limit-count` 插件，以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

为消费者 `john` 创建 `hmac-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
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

创建路由并配置 `hmac-auth` 插件以接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
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

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Mon, 21 Oct 2024 17:31:18 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="'}
```

使用生成的标头发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Date: Mon, 21 Oct 2024 17:31:18 GMT" -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="' -o /dev/null -s -w "%{http_code}\n") && \
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
