---
title: jwt-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - JWT Auth
  - jwt-auth
description: The jwt-auth Plugin supports the use of JSON Web Token (JWT) as a mechanism for clients to authenticate themselves before accessing Upstream resources.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/jwt-auth" />
</head>

## Description

The `jwt-auth` Plugin supports the use of [JSON Web Token (JWT)](https://jwt.io/) as a mechanism for clients to authenticate themselves before accessing Upstream resources.

Once enabled, the Plugin exposes an endpoint to create JWT credentials by [Consumers](../terminology/consumer.md). The process generates a token that client requests should carry to identify themselves to APISIX. The token can be included in the request URL query string, request header, or cookie. APISIX will then verify the token to determine if a request should be allowed or denied to access Upstream resources.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Indentifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logics as needed. If any of these values is not available, the corresponding header will not be added.

## Attributes

For Consumer/Credential:

| Name          | Type    | Required                                              | Default | Valid values                | Description                                                                                                                                                                                 |
|---------------|---------|-------------------------------------------------------|---------|-----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | True                                                  |         |     non-empty       | Unique key for a Consumer.                                                                                                                                                                  |
| secret        | string  | False                                                 |         |        non-empty        | Shared key used to sign and verify the JWT when the algorithm is symmetric. Required when using `HS256` or `HS512` as the algorithm. If unspecified, the secret will be auto-generated. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.       |
| public_key    | string  | True if `RS256` or `ES256` is set for the `algorithm` attribute. |         |                             | RSA or ECDSA public key. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.                      |
| algorithm     | string  | False                                                 | HS256 | ["HS256", "HS512", "RS256", "ES256"] | Encryption algorithm.                                                                                                                                                                       |
| exp           | integer | False                                                 | 86400   | [1,...]                     | Expiry time of the token in seconds.                                                                                                                                                        |
| base64_secret | boolean | False                                                 | false   |                             | Set to true if the secret is base64 encoded.                                                                                                                                                |
| lifetime_grace_period | integer | False                                         | 0       | [0,...]                     | Grace period in seconds. Used to account for clock skew between the server generating the JWT and the server validating the JWT.  |
| key_claim_name | string | False                                                 | key     |                             | The claim in the JWT payload that identifies the associated secret, such as `iss`. |

NOTE: `encrypt_fields = {"secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

For Routes or Services:

| Name   | Type   | Required | Default       | Description                                                         |
|--------|--------|----------|---------------|---------------------------------------------------------------------|
| header | string | False    | authorization | The header to get the token from.                                   |
| query  | string | False    | jwt           | The query string to get the token from. Lower priority than header. |
| cookie | string | False    | jwt           | The cookie to get the token from. Lower priority than query.        |
| hide_credentials| boolean | False    | false  | If true, do not pass the header, query, or cookie with JWT to Upstream services.  |
| key_claim_name  | string  | False    | key     | The name of the JWT claim that contains the user key (corresponds to Consumer's key attribute). |
| anonymous_consumer | string | False  | false  | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication.   |
| store_in_ctx     | boolean | False    | false   | Set to true will store the JWT payload in the request context (`ctx.jwt_auth_payload`). This allows lower-priority plugins that run afterwards on the same request to retrieve and use the JWT token. |

You can implement `jwt-auth` with [HashiCorp Vault](https://www.vaultproject.io/) to store and fetch secrets and RSA keys pairs from its [encrypted KV engine](https://developer.hashicorp.com/vault/docs/secrets/kv) using the [APISIX Secret](../terminology/secret.md) resource.

## Examples

The examples below demonstrate how you can work with the `jwt-auth` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Use JWT for Consumer Authentication

The following example demonstrates how to implement JWT for Consumer key authentication.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret"
      }
    }
  }'
```

Create a Route with `jwt-auth` plugin:

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

To issue a JWT for `jack`, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `jack-hs256-secret`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```text
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.0VDKUzNkSaa_H5g_rGNbNtDcKJ9fBGgcGC56AsVsV-I
```

Send a request to the Route with the JWT in the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
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

In 30 seconds, the token should expire. Send a request with the same token to verify:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 401 Unauthorized` response similar to the following:

```text
{"message":"failed to verify jwt"}
```

### Carry JWT in Request Header, Query String, or Cookie

The following example demonstrates how to accept JWT in specified header, query string, and cookie.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret"
      }
    }
  }'
```

Create a Route with `jwt-auth` Plugin, and specify that the request can either carry the token in the header, query, or the cookie:

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

To issue a JWT for `jack`, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `jack-hs256-secret`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```text
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.0VDKUzNkSaa_H5g_rGNbNtDcKJ9fBGgcGC56AsVsV-I
```

#### Verify With JWT in Header

Sending request with JWT in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "jwt-auth-header: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "Jwt-Auth-Header": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ",
    ...
  },
  ...
}
```

#### Verify With JWT in Query String

Sending request with JWT in the query string:

```shell
curl -i "http://127.0.0.1:9080/get?jwt-query=${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
{
  "args": {
    "jwt-query": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ"
  },
  "headers": {
    "Accept": "*/*",
    ...
  },
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://127.0.0.1/get?jwt-query=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ"
}
```

#### Verify With JWT in Cookie

Sending request with JWT in the cookie:

```shell
curl -i "http://127.0.0.1:9080/get" --cookie jwt-cookie=${jwt_token}
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Cookie": "jwt-cookie=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ",
    ...
  },
  ...
}
```

### Manage Secrets in Environment Variables

The following example demonstrates how to save `jwt-auth` Consumer key to an environment variable and reference it in configuration.

APISIX supports referencing system and user environment variables configured through the [NGINX `env` directive](https://nginx.org/en/docs/ngx_core_module.html#env).

Save the key to an environment variable:

```shell
JACK_JWT_AUTH_KEY=jack-key
```

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer and reference the environment variable in the key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "$env://JACK_JWT_AUTH_KEY",
        "secret": "jack-hs256-secret"
      }
    }
  }'
```

Create a Route with `jwt-auth` enabled:

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

To issue a JWT for `jack`, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `jack-hs256-secret`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```text
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.0VDKUzNkSaa_H5g_rGNbNtDcKJ9fBGgcGC56AsVsV-I
```

Sending request with JWT in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE2OTUxMzMxNTUsImtleSI6Imp3dC1rZXkifQ.jiKuaAJqHNSSQCjXRomwnQXmdkC5Wp5VDPRsJlh1WAQ",
    ...
  },
  ...
}
```

### Manage Secrets in Secret Manager

The following example demonstrates how to manage `jwt-auth` Consumer key in [HashiCorp Vault](https://www.vaultproject.io) and reference it in Plugin configuration.

Start a Vault development server in Docker:

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

APISIX currently supports [Vault KV engine version 1](https://developer.hashicorp.com/vault/docs/secrets/kv#kv-version-1). Enable it in Vault:

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"
```

You should see a response similar to the following:

```text
Success! Enabled the kv secrets engine at: kv/
```

Create a secret and configure the Vault address and other connection information:

```shell
curl "http://127.0.0.1:9180/apisix/admin/secrets/vault/jwt" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "https://127.0.0.1:8200"，
    "prefix": "kv/apisix",
    "token": "root"
  }'
```

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer and reference the secret in the key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "$secret://vault/jwt/jack/jwt-key",
        "secret": "vault-hs256-secret"
      }
    }
  }'
```

Create a Route with `jwt-auth` enabled:

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

Set `jwt-auth` key value to be `jwt-vault-key` in Vault:

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/jack jwt-key=jwt-vault-key"
```

You should see a response similar to the following:

```text
Success! Data written to: kv/apisix/jack
```

To issue a JWT, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `vault-hs256-secret`.
* Update payload with Consumer key `jwt-vault-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jwt-vault-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```text
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwibmJmIjoxNzI5MTMyMjcxfQ.faiN93LNP1lGSXqAb4empNJKMRWop8-KgnU58VQn1EE
```

Sending request with the token as header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwiZXhwIjoxNjk1MTM4NjM1fQ.Au2liSZ8eQXUJR3SJESwNlIfqZdNyRyxIJK03L4dk_g",
    ...
  },
  ...
}
```

### Sign JWT with RS256 Algorithm

The following example demonstrates how you can use asymmetric algorithms, such as RS256, to sign and validate JWT when implementing JWT for Consumer authentication. You will be generating RSA key pairs using [openssl](https://openssl-library.org/source/) and generating JWT using [JWT.io](https://jwt.io/#debugger-io) to better understand the composition of JWT.

Generate a 2048-bit RSA private key and extract the corresponding public key in PEM format:

```shell
openssl genrsa -out jwt-rsa256-private.pem 2048
openssl rsa -in jwt-rsa256-private.pem -pubout -out jwt-rsa256-public.pem
```

You should see `jwt-rsa256-private.pem` and `jwt-rsa256-public.pem` generated in your current working directory.

Visit [JWT.io's debugger](https://jwt.io/#debugger-io) and do the following:

* Select __RS256__ in the __Algorithm__ dropdown.
* Copy and paste the key content into the __Verify Signature__ section.
* Update the payload with `key` matching the Consumer key you would like to use; and `exp` or `nbf` in UNIX timestamp.

The configuration should look similar to the following:

<br />
<div style={{textAlign: 'center'}}>
<img
  src="https://static.apiseven.com/uploads/2024/12/12/SRe7AXMw_jwt_token.png"
  alt="complete configuration of JWT generation on jwt.io"
  width="70%"
/>
</div>
<br />

Copy the JWT on the left and save to an environment variable:

```shell
jwt_token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsImV4cCI6MTczNDIzMDQwMH0.XjqM0oszmCggwZs-8PUIlJv8wPJON1la2ET5v70E6TCE32Yq5ibrl-1azaK7IreAer3HtnVHeEfII2rR02v8xfR1TPIjU_oHov4qC-A4tLTbgqGVXI7fCy2WFm3PFh6MEKuRe6M3dCQtCAdkRRQrBr1gWFQZhV3TNeMmmtyIfuJpB7cp4DW5pYFsCcoE1Nw6Tz7dt8k0tPBTPI2Mv9AYfMJ30LHDscOaPNtz8YIk_TOkV9b9mhQudUJ7J_suCZMRxD3iL655jTp2gKsstGKdZa0_W9Reu4-HY3LSc5DS1XtfjuftpuUqgg9FvPU0mK_b0wT_Rq3lbYhcHb9GZ72qiQ
```

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer and configure the RSA keys:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "algorithm": "RS256",
        "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnE0h4k/GWfEbYO/yE2MPjHtNKDLNz4mv1KNIPLxY2ccjPYOtjuug+iZ4MujLV59YfrHriTs0H8jweQfff3pRSMjyEK+4qWTY3TeKBXIEa3pVDeoedSJrgjLBVio6xH7et8ir+QScScfLaJHGB4/l3DDGyEhO782a9teY8brn5hsWX5uLmDJvxtTGAHYi847XOcx2UneW4tZ8wQ6JGBSiSg5qAHan4dFZ7CpixCNNqEcSK6EQ7lKOLeFGG8ys/dHBIEasU4oMlCuJH77+XQQ/shchy+vm9oZfP+grLZkV+nKAd8MQZsid7ZJ/fiB/BmnhGrjtIfh98jwxSx4DgdLhdwIDAQAB\n-----END PUBLIC KEY-----",
        "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCcTSHiT8ZZ8Rtg7/ITYw+Me00oMs3Pia/Uo0g8vFjZxyM9g62O66D6Jngy6MtXn1h+seuJOzQfyPB5B99/elFIyPIQr7ipZNjdN4oFcgRrelUN6h51ImuCMsFWKjrEft63yKv5BJxJx8tokcYHj+XcMMbISE7vzZr215jxuufmGxZfm4uYMm/G1MYAdiLzjtc5zHZSd5bi1nzBDokYFKJKDmoAdqfh0VnsKmLEI02oRxIroRDuUo4t4UYbzKz90cEgRqxTigyUK4kfvv5dBD+yFyHL6+b2hl8/6CstmRX6coB3wxBmyJ3tkn9+IH8GaeEauO0h+H3yPDFLHgOB0uF3AgMBAAECggEARpY68Daw0Funzq5uN70r/3iLztSqx8hZpQEclXlF8wwQ6S33iqz1JSOMcwlZE7g9wfHd+jrHfndDypT4pVx7KxC86TZCghWuLrFvXqgwQM2dbcxGdwXVYZZEZAJsSeM19+/jYnFnl5ZoUVBMC4w79aX9j+O/6mKDUmjphHmxUuRCFjN0w7BRoYwmS796rSf1eoOcSXh2G9Ycc34DUFDfGpOzabndbmMfOz7W0DyUBG23fgLhNChTUGq8vMaqKXkQ8JKeKdEugSmRGz42HxjWoNlIGBDyB8tPNPT6SXsu/JBskdf9Gb71OWiub381oXC259sz+1K1REb1KSkgyC+bkQKBgQDKCnwXaf8aOIoJPCG53EqQfKScCIYQrvp1Uk3bs5tfYN4HcI3yAUnOqQ3Ux3eY9PfS37urlJXCfCbCnZ6P6xALZnN+aL2zWvZArlHvD6vnXiyevwK5IY+o2EW02h3A548wrGznQSsfX0tum22bEVlRuFfBbpZpizXwrV4ODSNhTwKBgQDGC27QQxah3yq6EbOhJJlJegjawVXEaEp/j4fD3qe/unLbUIFvCz6j9BAbgocDKzqXxlpTtIbnsesdLo7KM3MtYL0XO/87HIsBj9XCVgMkFCcM6YZ6fHnkJl0bs3haU4N9uI/wpokvfvXJp7iC9LUCseBdBj+N6T230HWiSbPjWQKBgQC8zzGKO/8vRNkSqkQmSczQ2/qE6p5G5w6eJy0lfOJdLswvDatJFpUf8PJA/6svoPYb9gOO5AtUNeuPAfeVLSnQTYzu+/kTrJTme0GMdAvE60gtjfmAgvGa64mw6gjWJk+1P92B+2/OIKMAmXXDbWIYMXqpBKzBs1vUMF/uJ68BlwKBgQDEivQem3YKj3/HyWmLstatpP7EmrqTgSzuC3OhX4b7L/5sySirG22/KKgTpSZ4bp5noeJiz/ZSWrAK9fmfkg/sKOV/+XsDHwCVPDnX86SKWbWnitp7FK2jTq94nlQC0H7edhvjqGLdUBJ9XoYu8MvzMLSJnXnVTHSDx832kU6FgQKBgQCbw4Eiu2IcOduIAokmsZl8Smh9ZeyhP2B/UBa1hsiPKQ6bw86QJr2OMbRXLBxtx+HYIfwDo4vXEE862PfoQyu6SjJBNmHiid7XcV06Z104UQNjP7IDLMMF+SASMqYoQWg/5chPfxBgIXnfWqw6TMmND3THY4Oj4Nhf4xeUg3HsaA==\n-----END PRIVATE KEY-----"
      }
    }
  }'
```

:::tip

You should add a newline character after the opening line and before the closing line, for example `-----BEGIN PRIVATE KEY-----\n......\n-----END PRIVATE KEY-----`.

The key content can be directly concatenated.

:::

Create a Route with the `jwt-auth` Plugin:

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

To verify, send a request to the Route with the JWT in the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsImV4cCI6MTczNDIzMDQwMH0.XjqM0oszmCggwZs-8PUIlJv8wPJON1la2ET5v70E6TCE32Yq5ibrl-1azaK7IreAer3HtnVHeEfII2rR02v8xfR1TPIjU_oHov4qC-A4tLTbgqGVXI7fCy2WFm3PFh6MEKuRe6M3dCQtCAdkRRQrBr1gWFQZhV3TNeMmmtyIfuJpB7cp4DW5pYFsCcoE1Nw6Tz7dt8k0tPBTPI2Mv9AYfMJ30LHDscOaPNtz8YIk_TOkV9b9mhQudUJ7J_suCZMRxD3iL655jTp2gKsstGKdZa0_W9Reu4-HY3LSc5DS1XtfjuftpuUqgg9FvPU0mK_b0wT_Rq3lbYhcHb9GZ72qiQ",
    ...
  }
}
```

### Add Consumer Custom ID to Header

The following example demonstrates how you can attach a Consumer custom ID to authenticated request in the `Consumer-Custom-Id` header, which can be used to implement additional logics as needed.

Create a Consumer `jack` with a custom ID label:

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

Create `jwt-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret"
      }
    }
  }'
```

Create a Route with `jwt-auth`:

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

To issue a JWT for `jack`, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `jack-hs256-secret`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```text
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.0VDKUzNkSaa_H5g_rGNbNtDcKJ9fBGgcGC56AsVsV-I
```

To verify, send a request to the Route with the JWT in the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should see an `HTTP/1.1 200 OK` response similar to the following, where `X-Consumer-Custom-Id` is attached:

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
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies by regular and anonymous consumers, where the anonymous Consumer does not need to authenticate and has less quotas.

Create a regular Consumer `jack` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

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

Create the `jwt-auth` Credential for the Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret"
      }
    }
  }'
```

Create an anonymous user `anonymous` and configure the `limit-count` Plugin to allow for a quota of 1 within a 30-second window:

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

Create a Route and configure the `jwt-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

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

To issue a JWT for `jack`, you could use [JWT.io's debugger](https://jwt.io/#debugger-io) or other utilities. If you are using [JWT.io's debugger](https://jwt.io/#debugger-io), do the following:

* Select __HS256__ in the __Algorithm__ dropdown.
* Update the secret in the __Verify Signature__ section to be `jack-hs256-secret`.
* Update payload with role `user`, permission `read`, and Consumer key `jack-key`; as well as `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT under the __Encoded__ section and save to a variable:

```shell
jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.hjtSsEILpko14zb8-ibyxrB2tA5biYY9JrFm3do69vs
```

To verify the rate limiting, send five consecutive requests with `jack`'s JWT:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Authorization: ${jwt_token}" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 5 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    2
```

Send five anonymous requests:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that only one request was successful:

```text
200:    1, 429:    4
```
