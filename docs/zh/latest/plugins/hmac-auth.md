---
title: hmac-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - HMAC Authentication
  - hmac-auth
description: 本文介绍了关于 Apache APISIX `hmac-auth` 插件的基本信息及使用方法。
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

`hmac-auth` 插件支持 HMAC（基于哈希的消息认证码）身份验证，作为一种确保请求完整性的机制，防止它们在传输过程中被修改。要使用该插件，您需要在 [Consumers](../terminology/consumer.md) 上配置 HMAC 密钥，并在 Routes 或 Services 上启用该插件。

启用后，插件会验证请求的 `Authorization` 标头中的 HMAC 签名，并检查传入请求是否来自可信来源。具体来说，当 APISIX 收到 HMAC 签名的请求时，会从 `Authorization` 标头中提取密钥 ID。然后，APISIX 会检索相应的消费者配置，包括密钥。如果密钥 ID 有效且存在，APISIX 会使用请求的 `Date` 标头和密钥生成 HMAC 签名。如果生成的签名与 `Authorization` 标头中提供的签名匹配，则请求经过身份验证并转发到上游服务。

该插件实现基于 [draft-cavage-http-signatures](https://www.ietf.org/archive/id/draft-cavage-http-signatures-12.txt)。

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

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

## 例子

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

在继续之前，创建一个示例使用者并配置其凭据，该配置将用于下面的所有示例。

创建一个消费者 `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

创建 `john` 的 `hmac-auth` 凭证：

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

### 在路由上实现 HMAC 身份验证

以下示例展示了如何在路由上实现 HMAC 身份验证。

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

生成签名。您可以使用以下 Python 代码片段或您选择的其他技术栈：

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # 密钥 ID
Secret_key = b"john-secret-key"    # 秘密密钥
request_method = "GET"             # HTTP 方法
request_path = "/get"              # 路由 URI
algorithm= "hmac-sha256"           # 可以在 allowed_algorithms 中使用其他算法

# 获取当前的 GMT 日期时间
# 注意：时钟偏差后签名将失效（默认 300s）
# 签名失效后可以重新生成，或者增加时钟
# 倾斜以延长建议的安全边界内的有效性
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# 构造签名字符串（有序）
# 日期和任何后续的自定义标头应小写并用
# 单空格字符，即 `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# 创建签名
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# 构造请求头
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# 打印
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
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### 向上游隐藏授权信息

如 [上一个示例](#implement-hmac-authentication-on-a-route) 所示，传递给上游的 `Authorization` 标头包含签名和所有其他详细信息。这可能会带来安全风险。

以下示例展示了如何防止这些信息被发送到上游服务。

更新插件配置以将 `hide_credentials` 设置为 `true`：

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

发送以下请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

您应该看到 `HTTP/1.1 200 OK` 响应，并注意到 `Authorization` 标头已被完全删除：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### 启用主体验证

以下示例显示如何启用主体验证以确保请求主体的完整性。

使用 `hmac-auth` 插件创建路由，如下所示：

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

生成签名。您可以使用以下 Python 代码片段或您选择的其他技术栈：

```python title="hmac-sig-digest-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"             # 密钥 ID
Secret_key = b"john-secret-key" # 秘密密钥
request_method = "POST"         # HTTP 方法
request_path = "/post"          # 路由 URI
algorithms= "hmac-sha256"       # 可以在 allowed_algorithms 中使用其他算法
body = '{"name": "world"}'      # 请求正文示例

# 获取当前的 GMT 日期时间
# 注意：时钟偏差（默认 300s）后签名将失效。
# 签名失效后可以重新生成，或者增加时钟
# 倾斜以延长建议的安全边界内的有效性
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# 构造签名字符串（有序）
# 日期和任何后续的自定义标头应小写并用
# 单空格字符，即 `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
)

# 创建签名
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# 创建请求正文的 SHA-256 digest 并对其进行 Base64 编码
body_digest = hashlib.sha256(body.encode('utf-8')).digest()
body_digest_base64 = base64.b64encode(body_digest).decode('utf-8')

# 构造请求头
headers = {
    "Date": gmt_time,
    "Digest": f"SHA-256={body_digest_base64}",
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date",'
        f'signature="{signature_base64}"'
    )
}

# 打印
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
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/post"
}
```

如果您发送的请求没有 digest 或 digest 无效：

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

以下示例展示了如何强制在请求的 HMAC 签名中对某些标头进行签名。

使用 `hmac-auth` 插件创建路由，该路由要求 HMAC 签名中存在三个标头：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
        "signed_headers": ["date","x-custom-header-a", "x-custom-header-b"]
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

生成签名。您可以使用以下 Python 代码片段或您选择的其他技术栈：

```python title="hmac-sig-req-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"             # 密钥 ID
Secret_key = b"john-secret-key" # 秘密密钥
request_method = "GET"          # HTTP 方法
request_path = "/get"           # 路由 URI
algorithms= "hmac-sha256"       # 可以在 allowed_algorithms 中使用其他算法
custom_header_a = "hello123"    # 必需的自定义标头
custom_header_b = "world456"    # 必需的自定义标头

# 获取当前的 GMT 日期时间
# 注意：时钟偏差后签名将失效（默认 300s）
# 签名失效后可以重新生成，或者增加时钟
# 倾斜以延长建议的安全边界内的有效性
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# 构造签名字符串（有序）
# 日期和任何后续的自定义标头应小写并用
# 单空格字符，即 `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
    f"x-custom-header-a: {custom_header_a}\n"
    f"x-custom-header-b: {custom_header_b}\n"
)

# 创建签名
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# 构造请求头
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

# 打印
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
    "X-Custom-Header-A": "hello123",
    "X-Custom-Header-B": "world456",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 103.97.2.206",
  "url": "http://127.0.0.1/get"
}
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
