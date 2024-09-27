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

When you are using custom Plugins, you can use the `public-api` Plugin to define a fixed, public API for a particular functionality. For example, you can create a public API endpoint `/apisix/batch-requests` for grouping multiple API requests in one request using the [batch-requests](./batch-requests.md) Plugin.

:::note

The public API added in a custom Plugin is not exposed by default and the user should manually configure a Route and enable the `public-api` Plugin on it.

:::

## Attributes

| Name | Type   | Required | Default | Description                                                                                                                                                  |
|------|--------|----------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri  | string | False    | ""      | URI of the public API. When setting up a Route, use this attribute to configure the original public API URI. |

## Example usage

The example below uses the [batch-requests](./batch-requests.md) Plugin and the [key-auth](./key-auth.md) Plugin along with the `public-api` Plugin. Refer to their documentation for its configuration. This step is omitted below and only explains the configuration of the `public-api` Plugin.

### Basic usage

You can enable the Plugin on a specific Route as shown below:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
      "uri": "/apisix/batch-requests",
      "plugins": {
        "public-api": {}
    }
}'
```

Now, if you make a request to the configured URI, you will receive a batch-requests response:

```shell
curl --location --request POST 'http://127.0.0.1:9080/apisix/batch-requests' \
--header 'Content-Type: application/json' \
--data '{
    "headers": {
        "Content-Type": "application/json",
        "admin-jwt":"xxxx"
    },
    "timeout": 500,
    "pipeline": [
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test"
        },
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test2"
        }
    ]
}'
```

```shell
[
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  },
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  }
]
```

### Using custom URI

You can also use a custom URI for exposing the API as shown below:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
      "uri": "/batch-requests-gifs",
      "plugins": {
        "public-api": {
            "uri": "/apisix/batch-requests"
        }
    }
}'
```

Now you can make requests to this new endpoint:

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
--header 'Content-Type: application/json' \
--data '{...}'
```

### Securing the Route

You can use the `key-auth` Plugin to add authentication and secure the Route:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/batch-requests-gifs",
    "plugins": {
        "public-api": {},
        "key-auth": {}
    }
}'
```

Now, only authenticated requests are allowed:

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
    -H "apikey: test-apikey"
    -H 'Content-Type: application/json' \
    --data '{...}'
```

```shell
HTTP/1.1 200 OK
```

The below request will fail:

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
    -H 'Content-Type: application/json' \
    --data '{...}'
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
