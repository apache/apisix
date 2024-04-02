---
title: public-api
keywords:
  - Apache APISIX
  - API Gateway
  - Public API
description: The public-api is used for exposing an API endpoint through a general HTTP API router.
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

The `public-api` is used for exposing an API endpoint through a general HTTP API router.

When you are using custom Plugins, you can use the `public-api` Plugin to define a fixed, public API for a particular functionality. For example, you can create a public API endpoint `/apisix/plugin/jwt/sign` for JWT authentication using the [jwt-auth](./jwt-auth.md) Plugin.

:::note

The public API added in a custom Plugin is not exposed by default and the user should manually configure a Route and enable the `public-api` Plugin on it.

:::

## Attributes

| Name | Type   | Required | Default | Description                                                                                                                                                  |
|------|--------|----------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri  | string | False    | ""      | URI of the public API. When setting up a Route, use this attribute to configure the original public API URI. |

## Example usage

The example below uses the [jwt-auth](./jwt-auth.md) Plugin and the [key-auth](./key-auth.md) Plugin along with the `public-api` Plugin. Refer to their documentation for it configuration. This step is omitted below and only explains the configuration of the `public-api` Plugin.

### Basic usage

You can enable the Plugin on a specific Route as shown below:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/apisix/plugin/jwt/sign",
    "plugins": {
        "public-api": {}
    }
}'
```

Now, if you make a request to the configured URI, you will receive a JWT response:

```shell
curl 'http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key'
```

### Using custom URI

You can also use a custom URI for exposing the API as shown below:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        }
    }
}'
```

Now you can make requests to this new endpoint:

```shell
curl 'http://127.0.0.1:9080/gen_token?key=user-key'
```

### Securing the Route

You can use the `key-auth` Plugin to add authentication and secure the Route:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        },
        "key-auth": {}
    }
}'
```

Now, only authenticated requests are allowed:

```shell
curl -i 'http://127.0.0.1:9080/gen_token?key=user-key' \
    -H "apikey: test-apikey"
```

```shell
HTTP/1.1 200 OK
```

The below request will fail:

```shell
curl -i 'http://127.0.0.1:9080/gen_token?key=user-key'
```

```shell
HTTP/1.1 401 Unauthorized
```

## Delete Plugin

To remove the `public-api` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/hello",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:1980": 1
    }
  }
}'
```
