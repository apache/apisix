---
title: batch-requests
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Batch Requests
description: This document contains information about the Apache APISIX batch-request Plugin.
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

After enabling the batch-requests plugin, users can assemble multiple requests into one request and send them to the gateway. The gateway will parse the corresponding requests from the request body and then individually encapsulate them into separate requests. Instead of the user initiating multiple HTTP requests to the gateway, the gateway will use the HTTP pipeline method, go through several stages such as route matching, forwarding to the corresponding upstream, and then return the combined results to the client after merging.

![batch-request](https://static.apiseven.com/uploads/2023/06/27/ATzEuOn4_batch-request.png)

In cases where the client needs to access multiple APIs, this will significantly improve performance.

:::note

The request headers in the user’s original request (except for headers starting with “Content-”, such as “Content-Type”) will be assigned to each request in the HTTP pipeline. Therefore, to the gateway, these HTTP pipeline requests sent to itself are no different from external requests initiated directly by users. They can only access pre-configured routes and will undergo a complete authentication process, so there are no security issues.

If the request headers of the original request conflict with those configured in the plugin, the request headers configured in the plugin will take precedence (except for the real_ip_header specified in the configuration file).

:::

## Attributes

None.

## API

This plugin adds `/apisix/batch-requests` as an endpoint.

:::note

You may need to use the [public-api](public-api.md) plugin to expose this endpoint.

:::

## Enable Plugin

You can enable the `batch-requests` Plugin by adding it to your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - batch-requests
```

## Configuration

By default, the maximum body size that can be sent to `/apisix/batch-requests` can't be larger than 1 MiB. You can change this configuration of the Plugin through the endpoint `apisix/admin/plugin_metadata/batch-requests`:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/batch-requests -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "max_body_size": 4194304
}'
```

## Metadata

| Name          | Type    | Required | Default | Valid values | Description                                |
| ------------- | ------- | -------- | ------- | ------------ | ------------------------------------------ |
| max_body_size | integer | True     | 1048576 | [1, ...]     | Maximum size of the request body in bytes. |

## Request and response format

This plugin will create an API endpoint in APISIX to handle batch requests.

### Request

| Name     | Type                               | Required | Default | Description                   |
| -------- |------------------------------------| -------- | ------- | ----------------------------- |
| query    | object                             | False    |         | Query string for the request. |
| headers  | object                             | False    |         | Headers for all the requests. |
| timeout  | integer                            | False    | 30000   | Timeout in ms.                |
| pipeline | array[[HttpRequest](#httprequest)] | True     |         | Details of the request.       |

#### HttpRequest

| Name       | Type    | Required | Default | Valid                                                                            | Description                                                                           |
| ---------- | ------- | -------- | ------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| version    | string  | False    | 1.1     | [1.0, 1.1]                                                                       | HTTP version.                                                                         |
| method     | string  | False    | GET     | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"] | HTTP method.                                                                          |
| query      | object  | False    |         |                                                                                  | Query string for the request. If set, overrides the value of the global query string. |
| headers    | object  | False    |         |                                                                                  | Headers for the request. If set, overrides the value of the global query string.      |
| path       | string  | True     |         |                                                                                  | Path of the HTTP request.                                                             |
| body       | string  | False    |         |                                                                                  | Body of the HTTP request.                                                             |
| ssl_verify | boolean | False    | false   |                                                                                  | Set to verify if the SSL certs matches the hostname.                                  |

### Response

The response is an array of [HttpResponses](#httpresponse).

#### HttpResponse

| Name    | Type    | Description            |
| ------- | ------- | ---------------------- |
| status  | integer | HTTP status code.      |
| reason  | string  | HTTP reason-phrase.    |
| body    | string  | HTTP response body.    |
| headers | object  | HTTP response headers. |

## Specifying a custom URI

You can specify a custom URI with the [public-api](public-api.md) Plugin.

You can set the URI you want when creating the Route and change the configuration of the public-api Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/br -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/batch-requests",
    "plugins": {
        "public-api": {
            "uri": "/apisix/batch-requests"
        }
    }
}'
```

## Example usage

First, you need to setup a Route to the batch request API. We will use the [public-api](public-api.md) Plugin for this:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/br -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/apisix/batch-requests",
    "plugins": {
        "public-api": {}
    }
}'
```

Now you can make a request to the batch request API (`/apisix/batch-requests`):

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

This will give a response:

```json
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

## Delete Plugin

You can remove `batch-requests` from your list of Plugins in your configuration file (`conf/config.yaml`).
