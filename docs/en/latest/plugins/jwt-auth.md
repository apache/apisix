---
title: jwt-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - JWT Auth
  - jwt-auth
description: This document contains information about the Apache APISIX jwt-auth Plugin.
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

## Description

The `jwt-auth` Plugin is used to add [JWT](https://jwt.io/) authentication to a [Service](../terminology/service.md) or a [Route](../terminology/route.md).

A [Consumer](../terminology/consumer.md) of the service then needs to provide a key through a query string, a request header or a cookie to verify its request.

## Attributes

For Consumer:

| Name          | Type    | Required                                              | Default | Valid values                | Description                                                                                                                                                                                 |
|---------------|---------|-------------------------------------------------------|---------|-----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | True                                                  |         |                             | Unique key for a Consumer.                                                                                                                                                                  |
| secret        | string  | False                                                 |         |                             | The encryption key. If unspecified, auto generated in the background. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.       |
| public_key    | string  | True if `RS256` or `ES256` is set for the `algorithm` attribute. |         |                             | RSA or ECDSA public key. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.                      |
| algorithm     | string  | False                                                 | "HS256" | ["HS256", "HS512", "RS256", "ES256"] | Encryption algorithm.                                                                                                                                                                       |
| exp           | integer | False                                                 | 86400   | [1,...]                     | Expiry time of the token in seconds.                                                                                                                                                        |
| base64_secret | boolean | False                                                 | false   |                             | Set to true if the secret is base64 encoded.                                                                                                                                                |
| lifetime_grace_period | integer | False                                         | 0       | [0,...]                     | Define the leeway in seconds to account for clock skew between the server that generated the jwt and the server validating it. Value should be zero (0) or a positive integer. |

NOTE: `encrypt_fields = {"secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

For Route:

| Name             | Type    | Required | Default       | Description                                                                                                                                                          |
|------------------|---------|----------|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| header           | string  | False    | authorization | The header to get the token from.                                                                                                                                    |
| query            | string  | False    | jwt           | The query string to get the token from. Lower priority than header.                                                                                                  |
| cookie           | string  | False    | jwt           | The cookie to get the token from. Lower priority than query.                                                                                                         |
| hide_credentials | boolean | False    | false         | Set to true will not pass the authorization request of header\query\cookie to the Upstream.                                                                          |
| key_claim_name   | string  | False    | key           | The name of the JWT claim that contains the user key (corresponds to Consumer's key attribute).                                                                      |
| store_in_ctx     | boolean | False    | false         | Set to true will store the JWT payload in the request context (`ctx.jwt_auth_payload`). This allows lower-priority plugins that run afterwards on the same request to retrieve and use the JWT token. |

You can implement `jwt-auth` with [HashiCorp Vault](https://www.vaultproject.io/) to store and fetch secrets and RSA keys pairs from its [encrypted KV engine](https://developer.hashicorp.com/vault/docs/secrets/kv) using the [APISIX Secret](../terminology/secret.md) resource.

## Enable Plugin

To enable the Plugin, you have to create a Consumer object with the JWT token and configure your Route to use JWT authentication.

First, you can create a Consumer object through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "secret": "my-secret-key"
        }
    }
}'
```

:::note

The `jwt-auth` Plugin uses the HS256 algorithm by default. To use the RS256 algorithm, you can configure the public key and specify the algorithm:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "kerouac",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----",
            "algorithm": "RS256"
        }
    }
}'
```

:::

Once you have created a Consumer object, you can configure a Route to authenticate requests:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "jwt-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

<!--
![create a consumer](../../../assets/images/plugin/jwt-auth-1.png)
![enable jwt plugin](../../../assets/images/plugin/jwt-auth-2.png)
![enable jwt from route or service](../../../assets/images/plugin/jwt-auth-3.png)
-->

## Example usage

You need first to issue a JWT token using some tool such as [JWT.io's debugger](https://jwt.io/#debugger-io) or a programming language.

:::note

When you are issuing a JWT token, you have to update the payload with `key` matching the credential key you would like to use; and `exp` or `nbf` in UNIX timestamp.

e.g. payload=`{"key": "user-key", "exp": 1727274983}`

:::

You can now use this token while making requests:

```shell
curl http://127.0.0.1:9080/index.html -H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI' -i
```

```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

Without the token, you will receive an error:

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

You can also pass the token as query parameters:

```shell
curl http://127.0.0.1:9080/index.html?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
```

```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

And also as cookies:

```shell
curl http://127.0.0.1:9080/index.html --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
```

```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

## Delete Plugin

To remove the `jwt-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
