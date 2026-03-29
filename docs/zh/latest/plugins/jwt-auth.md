---
title: jwt-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - JWT Auth
  - jwt-auth
description: jwt-auth 插件支持使用 JSON Web Token (JWT) 作为客户端在访问上游资源之前进行身份验证的机制。
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

`jwt-auth` 插件支持使用 [JSON Web Token (JWT)](https://jwt.io/) 作为客户端在访问上游资源之前进行身份验证的机制。

启用后，该插件会公开一个端点，供 [消费者](../terminology/consumer.md) 创建 JWT 凭据。该过程会生成一个令牌，客户端请求应携带该令牌以向 APISIX 标识自己。该令牌可以包含在请求 URL 查询字符串、请求标头或 cookie 中。然后，APISIX 将验证该令牌以确定是否应允许或拒绝请求访问上游资源。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Indentifier` 和其他消费者自定义标头（如已配置）。上游服务将能够区分消费者并根据需要实施其他逻辑。如果任何一个值不可用，则不会添加相应的标题。

## 属性

Consumer/Credential 端：

| 名称          | 类型     | 必选项 | 默认值  | 有效值                      | 描述                                                                                                          |
| ------------- | ------- | ----- | ------- | --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| key           | string  | 是    |         |                             | 消费者的唯一密钥。  |
| secret        | string  | 否    |         |                             | 当使用对称算法时，用于对 JWT 进行签名和验证的共享密钥。使用 `HS256` 或 `HS512` 作为算法时必填。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。   |
| public_key    | string  | 否    |         |                             | RSA 或 ECDSA 公钥， `algorithm` 属性选择 `RS256` 或 `ES256` 算法时必选。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。       |
| algorithm     | string  | 否    | "HS256" | ["HS256", "HS384", "HS512", "RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "EdDSA"] | 加密算法。                                                                                                      |
| exp           | integer | 否    | 86400   | [1,...]                     | token 的超时时间。                                                                                              |
| base64_secret | boolean | 否    | false   |                             | 当设置为 `true` 时，密钥为 base64 编码。                                                                                         |
| lifetime_grace_period | integer | 否    | 0  | [0,...]                  | 宽限期（以秒为单位）。用于解决生成 JWT 的服务器与验证 JWT 的服务器之间的时钟偏差。 |
| key_claim_name | string | 否                                                 | key     |                             | JWT payload 中的声明用于标识相关的秘密，例如 `iss`。 |

注意：schema 中还定义了 `encrypt_fields = {"secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Route 端：

| 名称   | 类型    | 必选项 | 默认值         | 描述                                                    |
| ------ | ------ | ------ | ------------- |---------------------------------------------------------|
| header | string | 否     | authorization | 设置我们从哪个 header 获取 token。                         |
| query  | string | 否     | jwt           | 设置我们从哪个 query string 获取 token，优先级低于 header。  |
| cookie | string | 否     | jwt           | 设置我们从哪个 cookie 获取 token，优先级低于 query。        |
| hide_credentials | boolean | 否     | false  | 如果为 true，则不要将 header、query 或带有 JWT 的 cookie 传递给上游服务。 |
| key_claim_name | string  | 否     | key           | 包含用户密钥（对应消费者的密钥属性）的 JWT 声明的名称。|
| anonymous_consumer | string | 否     | false  | 匿名消费者名称。如果已配置，则允许匿名用户绕过身份验证。  |
| store_in_ctx | boolean | 否     | false  | 设置为 `true` 将会将 JWT 负载存储在请求上下文 (`ctx.jwt_auth_payload`) 中。这允许在同一请求上随后运行的低优先级插件检索和使用 JWT 令牌。 |
| claims_to_verify | array[string] | 否 | ["exp", "nbf"] | ["exp", "nbf"] | 需要在 JWT 负载中验证的声明。 |

您可以使用 [HashiCorp Vault](https://www.vaultproject.io/) 实施 `jwt-auth`，以从其[加密的 KV 引擎](https://developer.hashicorp.com/vault/docs/secrets/kv) 使用 [APISIX Secret](../terminology/secret.md) 资源。

## 示例

以下示例演示了如何在不同场景中使用 `jwt-auth` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用 JWT 进行消费者身份验证

以下示例演示了如何使用 JWT 进行消费者密钥身份验证。

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

使用 `jwt-auth` 插件创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/headers",
    "plugins": {
      "jwt-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jack-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

将生成的 JWT 保存到变量中：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

使用 `Authorization` 标头中的 JWT 向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MjY2NDk2NDAsImtleSI6ImphY2sta2V5In0.kdhumNWrZFxjUvYzWLt4lFr546PNsr9TXuf0Az5opoM",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea951a-4d740d724bd2a44f174d4daf",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-jwt-auth",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

使用无效的令牌发送请求以验证：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MjY2NDk2NDAsImtleSI6ImphY2sta2V5In0.kdhumNWrZFxjU_random_random"
```

您应该收到类似于以下内容的 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"failed to verify jwt"}
```

### 在请求标头、查询字符串或 Cookie 中携带 JWT

以下示例演示如何在指定的标头、查询字符串和 Cookie 中接受 JWT。

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

创建一个带有 `jwt-auth` 插件的路由，并指定请求可以在标头、查询或 cookie 中携带令牌：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {
        "header": "jwt-auth-header",
        "query": "jwt-query",
        "cookie": "jwt-cookie"
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

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jack-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

将生成的 JWT 保存到变量中：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

#### 使用标头中的 JWT 进行验证

发送标头中包含 JWT 的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "jwt-auth-header: ${jwt_token}"
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "Jwt-Auth-Header": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    ...
  },
  ...
}
```

#### 在查询字符串中使用 JWT 进行验证

在查询字符串中使用 JWT 发送请求：

```shell
curl -i "http://127.0.0.1:9080/get?jwt-query=${jwt_token}"
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {
    "jwt-query": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU"
  },
  "headers": {
    "Accept": "*/*",
    ...
  },
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://127.0.0.1/get?jwt-query=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ"
}
```

#### 使用 Cookie 中的 JWT 进行验证

使用 cookie 中的 JWT 发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" --cookie jwt-cookie=${jwt_token}
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Cookie": "jwt-cookie=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    ...
  },
  ...
}
```

### 在环境变量中管理密钥

以下示例演示了如何将 `jwt-auth` 消费者密钥保存到环境变量并在配置中引用它。

APISIX 支持引用通过 [NGINX `env` 指令](https://nginx.org/en/docs/ngx_core_module.html#env) 配置的系统和用户环境变量。

将密钥保存到环境变量中：

```shell
export JACK_JWT_SECRET=jack-hs256-secret-that-is-very-long
```

:::tip

如果您在 Docker 中运行 APISIX，需要在启动容器时使用 `-e` flag 设置环境变量。

:::

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭证并引用环境变量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "$env://JACK_JWT_SECRET"
      }
    }
  }'
```

创建启用 `jwt-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jack-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

将生成的 JWT 保存到变量中：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

发送标头中包含 JWT 的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

### 在 Secret Manager 中管理 Secret

以下示例演示了如何在 [HashiCorp Vault](https://www.vaultproject.io) 中管理 `jwt-auth` 消费者密钥，并在插件配置中引用它。

在 Docker 中启动 Vault 开发服务器：

```shell
docker run -d \
  --name vault \
  -p 8200:8200 \
  --cap-add IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  vault:1.9.0 \
  vault server -dev
```

APISIX 目前支持 [Vault KV 引擎版本 1](https://developer.hashicorp.com/vault/docs/secrets/kv#kv-version-1)。请在 Vault 中启用它：

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"
```

您应该会看到类似以下内容的响应：

```text
Success! Enabled the kv secrets engine at: kv/
```

创建一个 Secret，并配置 Vault 地址和其他连接信息。根据情况相应地更新 Vault 地址：

```shell
curl "http://127.0.0.1:9180/apisix/admin/secrets/vault/jwt" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "https://127.0.0.1:8200",
    "prefix": "kv/apisix",
    "token": "root"
  }'
```

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭证并引用 Secret：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jwt-vault-key",
        "secret": "$secret://vault/jwt/jack/jwt-secret"
      }
    }
  }'
```

创建启用 `jwt-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

在 Vault 中将 `jwt-auth` 键值设置为 `vault-hs256-secret-that-is-very-long`：

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/jack jwt-secret=vault-hs256-secret-that-is-very-long"
```

您应该会看到类似以下内容的响应：

```text
Success! Data written to: kv/apisix/jack
```

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `vault-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jwt-vault-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jwt-vault-key",
    "nbf": 1729132271
  }
  ```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwibmJmIjoxNzI5MTMyMjcxfQ.i2pLj7QcQvnlSjB7iV5V522tIV43boQRtee7L0rwlkQ
```

发送带有令牌作为标头的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

### 使用 RS256 算法签名 JWT

以下示例演示了如何在实现 JWT 消费者身份验证时使用非对称算法（例如 RS256）对 JWT 进行签名和验证。您将使用 [openssl](https://openssl-library.org/source/) 生成 RSA 密钥对，并使用 [JWT.io](https://jwt.io) 生成 JWT，以便更好地理解 JWT 的组成。

生成一个 2048 位 RSA 私钥，并提取相应的 PEM 格式公钥：

```shell
openssl genrsa -out jwt-rsa256-private.pem 2048
openssl rsa -in jwt-rsa256-private.pem -pubout -out jwt-rsa256-public.pem
```

您应该看到在当前工作目录中生成的 `jwt-rsa256-private.pem` 和 `jwt-rsa256-public.pem`。

访问 [JWT.io 的 JWT 编码器](https://jwt.io) 并执行以下操作：

* 填写 `RS256` 作为算法。
* 将私钥内容复制并粘贴到 __SIGN JWT: PRIVATE KEY__ 部分。
* 使用消费者密钥 `jack-key` 更新有效负载；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.K-I13em84kAcyH1jfIJl7ls_4jlwg1GzEzo5_xrDu-3wt3Xa3irS6naUsWpxX-a-hmcZZxRa9zqunqQjUP4kvn5e3xg2f_KyCR-_ZbwqYEPk3bXeFV1l4iypv6z5L7W1Niharun-dpMU03b1Tz64vhFx6UwxNL5UIZ7bunDAo_BXZ7Xe8rFhNHvIHyBFsDEXIBgx8lNYMq8QJk3iKxZhZZ5Om7lgYjOOKRgew4WkhBAY0v1AkO77nTlvSK0OEeeiwhkROyntggyx-S-U222ykMQ6mBLxkP4Cq5qHwXD8AUcLk5mhEij-3QhboYnt7yhKeZ3wDSpcjDvvL2aasC25ng
```

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭证并配置 RSA 密钥：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "algorithm": "RS256",
        "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoTxe7ZPycrEP0SK4OBA2\n0OUQsDN9gSFSHVvx/t++nZNrFxzZnV6q6/TRsihNXUIgwaOu5icFlIcxPL9Mf9UJ\na5/XCQExp1TxpuSmjkhIFAJ/x5zXrC8SGTztP3SjkhYnQO9PKVXI6ljwgakVCfpl\numuTYqI+ev7e45NdK8gJoJxPp8bPMdf8/nHfLXZuqhO/btrDg1x+j7frDNrEw+6B\nCK2SsuypmYN+LwHfaH4Of7MQFk3LNIxyBz0mdbsKJBzp360rbWnQeauWtDymZxLT\nATRNBVyl3nCNsURRTkc7eyknLaDt2N5xTIoUGHTUFYSdE68QWmukYMVGcEHEEPkp\naQIDAQAB\n-----END PUBLIC KEY-----"
      }
    }
  }'
```

:::tip

您应该在起始行之后和结束行之前添加换行符，例如 `-----BEGIN PUBLIC KEY-----\n......\n-----END PUBLIC KEY-----`。

密钥内容可以直接连接。

:::

使用 `jwt-auth` 插件创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/headers",
    "plugins": {
      "jwt-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

使用 `Authorization` 标头中的 JWT 向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

### 将消费者自定义 ID 添加到标头

以下示例演示了如何在 `Consumer-Custom-Id` 标头中将消费者自定义 ID 附加到已验证的请求，该 ID 可用于根据需要实现其他逻辑。

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

为消费者创建 `jwt-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

使用 `jwt-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-auth-route",
    "uri": "/anything",
    "plugins": {
      "jwt-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jack-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

为了验证，使用 `Authorization` 标头中的 JWT 向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

您应该会看到类似以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-6873b19d-329331db76e5e7194c942b47",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-jwt-auth",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### 匿名消费者的速率限制

以下示例演示了如何为普通消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者无需身份验证，且配额较少。

创建一个普通消费者 `jack`，并配置 `limit-count` 插件，允许在 30 秒内使用 3 个配额：

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

为消费者 `jack` 创建 `jwt-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
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

创建一个路由并配置 `jwt-auth` 插件以接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-auth-route",
    "uri": "/anything",
    "plugins": {
      "jwt-auth": {
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

要为 `jack` 颁发 JWT，您可以使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他实用程序。如果您使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 填写 `HS256` 作为算法。
* 将 __Valid secret__ 部分中的密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 使用消费者密钥 `jack-key` 更新有效 payload；并添加 `exp` 或 `nbf` UNIX 时间戳。

  您的 payload 应类似于以下内容：

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

将生成的 JWT 复制到 __Encoded__ 部分并保存到变量中：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

为了验证速率限制，请使用 jack 的 JWT 连续发送五个请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Authorization: ${jwt_token}" -o /dev/null -s -w "%{http_code}\n") && \
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
