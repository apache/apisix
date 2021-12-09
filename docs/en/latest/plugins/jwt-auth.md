---
title: jwt-auth
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

## Summary

- [Summary](#summary)
- [Name](#name)
- [Attributes](#attributes)
  - [Vault Plugin Attributes](#vault-plugin-attributes)
- [API](#api)
- [How To Enable](#how-to-enable)
  - [Enable jwt-auth with Vault Compatibility](#enable-jwt-auth-with-vault-compatibility)
- [Test Plugin](#test-plugin)
    - [Get the Token in `jwt-auth` Plugin:](#get-the-token-in-jwt-auth-plugin)
    - [Try Request with Token](#try-request-with-token)
- [Disable Plugin](#disable-plugin)

## Name

`jwt-auth` is an authentication plugin that need to work with `consumer`. Add JWT Authentication to a `service` or `route`.

The `consumer` then adds its key to the query string parameter, request header, or `cookie` to verify its request.

For more information on JWT, refer to [JWT](https://jwt.io/) for more information.

`jwt-auth` plugin can be integrated with HashiCorp Vault for storing and fetching secrets, RSA key pairs from its encrypted kv engine. See the examples below to have a overview of how things works.

## Attributes

| Name          | Type    | Requirement | Default | Valid                       | Description                                                                                                                                      |
|:--------------|:--------|:------------|:--------|:----------------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------|
| key           | string  | required    |         |                             | different `consumer` have different value, it's unique. different `consumer` use the same `key`, and there will be a request matching exception. |
| secret        | string  | optional    |         |                             | encryption key. if you do not specify, the value is auto-generated in the background.                                                            |
| public_key    | string  | optional    |         |                             | RSA public key, required when `algorithm` attribute selects `RS256` algorithm.                                                                   |
| private_key   | string  | optional    |         |                             | RSA private key, required when `algorithm` attribute selects `RS256` algorithm.                                                                  |
| algorithm     | string  | optional    | "HS256" | ["HS256", "HS512", "RS256"] | encryption algorithm.                                                                                                                            |
| exp           | integer | optional    | 86400   | [1,...]                     | token's expire time, in seconds                                                                                                                  |
| base64_secret | boolean | optional    | false   |                             | whether secret is base64 encoded                                                                                                                 |
| vault | dictionary | optional    |    |                             | whether vault to be used for secret or public key and private key could be referenced from vault storage engine. ( see vault config here ) |

### Vault Plugin Attributes

To enable vault plugin, first visit the [config-default.yaml](https://github.com/apache/apisix/blob/master/conf/config-default.yaml) and update the yaml vault attributes with your vault server configuration.

| Name          | Type    | Requirement | Default | Valid                       | Description                                                                                                                                      |
|:--------------|:--------|:------------|:--------|:----------------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------|
| vault -> path | string | optional    |  |                             | If path is specified, vault uses this kv engine path for storing and retrival of secrets, public and private key. Else the plugin uses default path as `kv/apisix/jwt-auth/key/<jwt-auth.key>`. |
| vault -> add_prefix | boolean | optional    |  true  |                             | we suggests storing keys related to APISIX under kv/apisix namespace (can be configured with config-default.yaml vault.prefix field) for better key management, policy setup etc. If the field is disabled, the vault path specified under the consumer config will be treated as absolute path - for retrival and storing secrets the vault.prefix in yaml config won't be appeneded. |

## API

This plugin will add `/apisix/plugin/jwt/sign` to sign.
You may need to use [interceptors](../plugin-interceptors.md) to protect it.

## How To Enable

1. set a consumer and config the value of the `jwt-auth` option

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

`jwt-auth` uses the `HS256` algorithm by default, and if you use the `RS256` algorithm, you need to specify the algorithm and configure the public key and private key, as follows:

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

2. add a Route or add a Service, and enable the `jwt-auth` plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### Enable jwt-auth with Vault Compatibility

Sometimes, it's quite natural in production to have a centralized key management solution like vault where you don't have to update the APISIX consumer each time some part of your organization changes the signing secret key (secret for HS256/HS512 or public_key and private_key for RS256). APISIX got you covered here. The `jwt-auth` is capable of referencing keys from vault.

**Note**: For early version of this integration support, the plugin expects the key name of secrets stored into the vault path is among [ `secret`, `public_key`, `private_key` ] to successfully use the key. In next release we are going to add the support of referencing custom named keys.

To enable vault compatibility, just add the empty vault object (minimalistic configuration) inside the jwt-auth plugin.

1. use vault for HS256 keystore.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "vault": {}
        }
    }
}'
```

As no secret key is provided for HS256 algorithm, the plugin generates one and store it into vault kv engine having path `<vault.prefix from default-conf.yaml>/jwt-auth/key/user-key` with data `secret=<16 byte hex encoded string>`.

2. You have stored signing secret in some path inside vault and you want to use it.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "vault": {
                "path": "kv/some/random/path",
                "add_prefix": false
            }
        }
    }
}'
```

Here the plugin looks up for key `secret` inside vault path (`kv/some/random/path`) mentioned in the consumer config and uses it for subsequent signing and jwt verification. If the key is not found in the same path, the plugin generates a hex encoded string and store that into the same path (same as option 1 inside [here](#enable-jwt-auth-with-vault-compatibility)).

3. RS256 rsa keypairs, both public and private keys are stored into vault.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "algorithm": "RS256",
            "vault": {
                "path": "kv/some/random/path",
                "add_prefix": false
            }
        }
    }
}'
```

The plugin looks up for `public_key` and `private_key` keys inside vault kv path mentioned inside plugin vault configuration. If not found, it returns a key not found error.

4. public key in consumer configuration, while the private key is in vault.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "algorithm": "RS256",
            "public_key": "-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----"
            "vault": {
                "path": "kv/some/random/path",
                "add_prefix": false
            }
        }
    }
}'
```

This plugin uses rsa public key from consumer configuration and uses the private key directly fetched from vault.

You can use [APISIX Dashboard](https://github.com/apache/apisix-dashboard) to complete the above operations through the web console.

1. Add a Consumer through the web console:

![create a consumer](../../../assets/images/plugin/jwt-auth-1.png)

then add jwt-auth plugin in the Consumer page:
![enable jwt plugin](../../../assets/images/plugin/jwt-auth-2.png)

2. Create a Route or Service object and enable the jwt-auth plugin:

![enable jwt from route or service](../../../assets/images/plugin/jwt-auth-3.png)

## Test Plugin

#### Get the Token in `jwt-auth` Plugin:

* without extension payload:

```shell
$ curl http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI
```

* with extension payload:

```shell
$ curl -G --data-urlencode 'payload={"uid":10000,"uname":"test"}' http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key -i
HTTP/1.1 200 OK
Date: Wed, 21 Apr 2021 06:43:59 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.4

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1bmFtZSI6InRlc3QiLCJ1aWQiOjEwMDAwLCJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTYxOTA3MzgzOX0.jI9-Rpz1gc3u8Y6lZy8I43RXyCu0nSHANCvfn0YZUCY
```

#### Try Request with Token

* without token:

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

* request header with token:

```shell
$ curl http://127.0.0.1:9080/index.html -H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* request params with token:

```shell
$ curl http://127.0.0.1:9080/index.html?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* request cookie with token:

```shell
$ curl http://127.0.0.1:9080/index.html --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
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

When you want to disable the `jwt-auth` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
