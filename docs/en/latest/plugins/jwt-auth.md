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
| secret        | string  | False                                                 |         |        non-empty        | Shared key used to sign and verify the JWT when the algorithm is symmetric. Required when using `HS256` or `HS512` as the algorithm. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.       |
| public_key    | string  | True if `RS256` or `ES256` is set for the `algorithm` attribute. |         |                             | RSA or ECDSA public key. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.                      |
| algorithm     | string  | False                                                 | HS256 | ["HS256", "HS384", "HS512", "RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "EdDSA"] | Encryption algorithm.                                                                                                                                                                       |
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
| realm            | string  | False    | jwt     | The realm to include in the `WWW-Authenticate` header when authentication fails. |
| claims_to_verify | array[string] | False | ["exp", "nbf"] | ["exp", "nbf"] | The claims that need to be verified in the JWT payload. |

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

Create `jwt-auth` Credential for the consumer:

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

Create a Route with `jwt-auth` Plugin:

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

To issue a JWT for `jack`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `jack-hs256-secret-that-is-very-long`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

Send a request to the Route with the JWT in the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

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

Send a request with an invalid token:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MjY2NDk2NDAsImtleSI6ImphY2sta2V5In0.kdhumNWrZFxjU_random_random"
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
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

Create a Route with `jwt-auth` plugin, and specify the request parameters carrying the token:

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

To issue a JWT for `jack`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `jack-hs256-secret-that-is-very-long`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

#### Verify With JWT in Header

Sending request with JWT in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "jwt-auth-header: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

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

#### Verify With JWT in Query String

Sending request with JWT in the query string:

```shell
curl -i "http://127.0.0.1:9080/get?jwt-query=${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

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

#### Verify With JWT in Cookie

Sending request with JWT in the cookie:

```shell
curl -i "http://127.0.0.1:9080/get" --cookie jwt-cookie=${jwt_token}
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

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

### Manage Secrets in Environment Variables

The following example demonstrates how to save `jwt-auth` Consumer key to an environment variable and reference it in configuration.

APISIX supports referencing system and user environment variables configured through the [NGINX `env` directive](https://nginx.org/en/docs/ngx_core_module.html#env).

Save the key to an environment variable:

```shell
export JACK_JWT_SECRET=jack-hs256-secret-that-is-very-long
```

:::tip

If you are running APISIX in Docker, you should set the environment variable using the `-e` flag when starting the container.

:::

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer and reference the environment variable:

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

To issue a JWT for `jack`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `jack-hs256-secret-that-is-very-long`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

Sending request with JWT in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response.

### Manage Secrets in Secret Manager

The following example demonstrates how to manage `jwt-auth` consumer key in [HashiCorp Vault](https://www.vaultproject.io) and reference it in plugin configuration.

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

Create a Secret and configure the Vault address and other connection information. Update the Vault address accordingly:

```shell
curl "http://127.0.0.1:9180/apisix/admin/secrets/vault/jwt" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "https://127.0.0.1:8200",
    "prefix": "kv/apisix",
    "token": "root"
  }'
```

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "username": "jack"
  }'
```

Create `jwt-auth` Credential for the Consumer and reference the Secret:

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

Create a Route with `jwt-auth` enabled:

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

Set `jwt-auth` key value to be `vault-hs256-secret-that-is-very-long` in Vault:

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/jack jwt-secret=vault-hs256-secret-that-is-very-long"
```

You should see a response similar to the following:

```text
Success! Data written to: kv/apisix/jack
```

To issue a JWT, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `vault-hs256-secret-that-is-very-long`.
* Update payload with consumer key `jwt-vault-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jwt-vault-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwibmJmIjoxNzI5MTMyMjcxfQ.i2pLj7QcQvnlSjB7iV5V522tIV43boQRtee7L0rwlkQ
```

Send a request with the token in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response.

### Sign JWT with RS256 Algorithm

The following example demonstrates how you can use asymmetric algorithms, such as RS256, to sign and validate JWT when implementing JWT for Consumer authentication. You will be generating RSA key pairs using [openssl](https://openssl-library.org/source/) and generating JWT using [JWT.io](https://jwt.io) to better understand the composition of JWT.

Generate a 2048-bit RSA private key and extract the corresponding public key in PEM format:

```shell
openssl genrsa -out jwt-rsa256-private.pem 2048
openssl rsa -in jwt-rsa256-private.pem -pubout -out jwt-rsa256-public.pem
```

You should see `jwt-rsa256-private.pem` and `jwt-rsa256-public.pem` generated in your current working directory.

Visit [JWT.io's JWT encoder](https://jwt.io) and do the following:

* Fill in `RS256` as the algorithm.
* Copy and paste the private key content into the __SIGN JWT: PRIVATE KEY__ section.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.K-I13em84kAcyH1jfIJl7ls_4jlwg1GzEzo5_xrDu-3wt3Xa3irS6naUsWpxX-a-hmcZZxRa9zqunqQjUP4kvn5e3xg2f_KyCR-_ZbwqYEPk3bXeFV1l4iypv6z5L7W1Niharun-dpMU03b1Tz64vhFx6UwxNL5UIZ7bunDAo_BXZ7Xe8rFhNHvIHyBFsDEXIBgx8lNYMq8QJk3iKxZhZZ5Om7lgYjOOKRgew4WkhBAY0v1AkO77nTlvSK0OEeeiwhkROyntggyx-S-U222ykMQ6mBLxkP4Cq5qHwXD8AUcLk5mhEij-3QhboYnt7yhKeZ3wDSpcjDvvL2aasC25ng
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
        "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoTxe7ZPycrEP0SK4OBA2\n0OUQsDN9gSFSHVvx/t++nZNrFxzZnV6q6/TRsihNXUIgwaOu5icFlIcxPL9Mf9UJ\na5/XCQExp1TxpuSmjkhIFAJ/x5zXrC8SGTztP3SjkhYnQO9PKVXI6ljwgakVCfpl\numuTYqI+ev7e45NdK8gJoJxPp8bPMdf8/nHfLXZuqhO/btrDg1x+j7frDNrEw+6B\nCK2SsuypmYN+LwHfaH4Of7MQFk3LNIxyBz0mdbsKJBzp360rbWnQeauWtDymZxLT\nATRNBVyl3nCNsURRTkc7eyknLaDt2N5xTIoUGHTUFYSdE68QWmukYMVGcEHEEPkp\naQIDAQAB\n-----END PUBLIC KEY-----"
      }
    }
  }'
```

:::tip

You should add a newline character after the opening line and before the closing line, for example `-----BEGIN PUBLIC KEY-----\n......\n-----END PUBLIC KEY-----`.

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

You should receive an `HTTP/1.1 200 OK` response.

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
        "secret": "jack-hs256-secret-that-is-very-long"
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

To issue a JWT for `jack`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `jack-hs256-secret-that-is-very-long`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

To verify, send a request to the Route with the JWT in the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

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
        "secret": "jack-hs256-secret-that-is-very-long"
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

To issue a JWT for `jack`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the __Valid secret__ section to be `jack-hs256-secret-that-is-very-long`.
* Update payload with Consumer key `jack-key`; and add `exp` or `nbf` in UNIX timestamp.

  Your payload should look similar to the following:

  ```json
  {
    "key": "jack-key",
    "nbf": 1729132271
  }
  ```

Copy the generated JWT and save to a variable:

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
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
