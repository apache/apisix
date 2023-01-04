---
title: jwt-auth
keywords:
  - APISIX
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

The `jwt-auth` Plugin can be integrated with [HashiCorp Vault](https://www.vaultproject.io/) to store and fetch secrets and RSA keys pairs from its [encrypted KV engine](https://www.vaultproject.io/docs/secrets/kv). Learn more from the [examples](#enable-jwt-auth-with-vault-compatibility) below.

## Attributes

For Consumer:

| Name          | Type    | Required                                              | Default | Valid values                | Description                                                                                                                                                                                 |
|---------------|---------|-------------------------------------------------------|---------|-----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | True                                                  |         |                             | Unique key for a Consumer.                                                                                                                                                                  |
| secret        | string  | False                                                 |         |                             | The encryption key. If unspecified, auto generated in the background.                                                                                                                       |
| public_key    | string  | True if `RS256` or `ES256` is set for the `algorithm` attribute. |         |                             | RSA or ECDSA public key.                                                                                                                                                                             |
| private_key   | string  | True if `RS256` or `ES256` is set for the `algorithm` attribute. |         |                             | RSA or ECDSA private key.                                                                                                                                                                            |
| algorithm     | string  | False                                                 | "HS256" | ["HS256", "HS512", "RS256", "ES256"] | Encryption algorithm.                                                                                                                                                                       |
| exp           | integer | False                                                 | 86400   | [1,...]                     | Expiry time of the token in seconds.                                                                                                                                                        |
| base64_secret | boolean | False                                                 | false   |                             | Set to true if the secret is base64 encoded.                                                                                                                                                |
| vault         | object  | False                                                 |         |                             | Set to true to use Vault for storing and retrieving secret (secret for HS256/HS512  or public_key and private_key for RS256/ES256). By default, the Vault path is `kv/apisix/consumer/<consumer_name>/jwt-auth`. |
| lifetime_grace_period | integer | False                                         | 0       | [0,...]                     | Define the leeway in seconds to account for clock skew between the server that generated the jwt and the server validating it. Value should be zero (0) or a positive integer. |

NOTE: `encrypt_fields = {"secret", "private_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

:::info IMPORTANT

To enable Vault integration, you have to first update your configuration file (`conf/config.yaml`) with your Vault server configuration, host address and access token.

Refer to the Vault attributes in the default configuration file ([config-default.yaml](https://github.com/apache/apisix/blob/master/conf/config-default.yaml)) to learn more about these configurations.

:::

For Route:

| Name   | Type   | Required | Default       | Description                                                         |
|--------|--------|----------|---------------|---------------------------------------------------------------------|
| header | string | False    | authorization | The header to get the token from.                                   |
| query  | string | False    | jwt           | The query string to get the token from. Lower priority than header. |
| cookie | string | False    | jwt           | The cookie to get the token from. Lower priority than query.        |
| hide_credentials | boolean | False     | false  | Set to true will not pass the authorization request of header\query\cookie to the Upstream.|

## API

This Plugin adds `/apisix/plugin/jwt/sign` as an endpoint.

:::note

You may need to use the [public-api](public-api.md) plugin to expose this endpoint.

:::

## Enabling the Plugin

To enable the Plugin, you have to create a Consumer object with the JWT token and configure your Route to use JWT authentication.

First, you can create a Consumer object through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

The `jwt-auth` Plugin uses the HS256 algorithm by default. To use the RS256 algorithm, you can configure the public key and private key and specify the algorithm:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "kerouac",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----",
            "private_key": "-----BEGIN RSA PRIVATE KEY-----\n……\n-----END RSA PRIVATE KEY-----",
            "algorithm": "RS256"
        }
    }
}'
```

:::

Once you have created a Consumer object, you can configure a Route to authenticate requests:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### Usage with HashiCorp Vault

[HashiCorp Vault](https://www.vaultproject.io/) offers a centralized key management solution and it can be used along with APISIX for authentication.

So, if your organization frequently changes the secret/keys (secret for HS256/HS512 or public_key and private_key for RS256) and you don't want to update the APISIX consumer each time or if you don't want to use the key through the Admin API (to reduce secret sprawl), you can use Vault and the `jwt-auth` Plugin.

:::note

The current version of Apache APISIX expects the key names of the secrets stored in Vault to be among `secret`, `public_key`, and `private_key`. The former one is for the HS256/HS512 algorithm and the latter two are for the RS256 algorithm.

Support for custom names will be added in a future release.

:::

To use Vault, you can add an empty vault object in your configuration.

For example, if you have a stored HS256 signing secret inside Vault, you can use it in APISIX by:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "key-1",
            "vault": {}
        }
    }
}'
```

The Plugin will look for a key "secret" in the provided Vault path (`<vault.prefix>/consumer/jack/jwt-auth`) and uses it for JWT authentication. If the key is not found in the same path, the Plugin logs an error and JWT authentication fails.

:::note

The `vault.prefix` should be set in your configuration file (`conf/config.yaml`) file based on the base path you have chosen while enabling the Vault kv secret engine.

For example, if you did `vault secrets enable -path=foobar kv`, you should use `foobar` in `vault.prefix`.

:::

If the key is not found in this path, the Plugin will log an error.

And for RS256, both the public and private keys should stored in Vault and it can be configured by:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "rsa-keypair",
            "algorithm": "RS256",
            "vault": {}
        }
    }
}'
```

The Plugin will look for keys "public_key" and "private_key" in the provided Vault path (`<vault.prefix>/consumer/jack/jwt-auth`) and uses it for JWT authentication.

If the key is not found in this path, the Plugin will log an error.

You can also configure the `public_key` in the Consumer configuration and use the `private_key` stored in Vault:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "rico",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "algorithm": "RS256",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----"
            "vault": {}
        }
    }
}'
```

You can also use the [APISIX Dashboard](/docs/dashboard/USER_GUIDE) to complete the operation through a web UI.

<!--
![create a consumer](../../../assets/images/plugin/jwt-auth-1.png)
![enable jwt plugin](../../../assets/images/plugin/jwt-auth-2.png)
![enable jwt from route or service](../../../assets/images/plugin/jwt-auth-3.png)
-->

## Example usage

You need to first setup a Route for an API that signs the token using the [public-api](public-api.md) Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/jas -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/apisix/plugin/jwt/sign",
    "plugins": {
        "public-api": {}
    }
}'
```

Now, we can get a token:

- Without extension payload:

```shell
curl http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
```

```
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI
```

- With extension payload:

```shell
curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
```

```
HTTP/1.1 200 OK
Date: Wed, 21 Apr 2021 06:43:59 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.4

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1bmFtZSI6InRlc3QiLCJ1aWQiOjEwMDAwLCJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTYxOTA3MzgzOX0.jI9-Rpz1gc3u8Y6lZy8I43RXyCu0nSHANCvfn0YZUCY
```

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

## Disable Plugin

To disable the `jwt-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
