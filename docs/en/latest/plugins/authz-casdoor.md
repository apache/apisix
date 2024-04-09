---
title: authz-casdoor
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Authz Casdoor
  - authz-casdoor
description: This document contains information about the Apache APISIX authz-casdoor Plugin.
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

The `authz-casdoor` Plugin can be used to add centralized authentication with [Casdoor](https://casdoor.org/).

## Attributes

| Name          | Type   | Required | Description                                  |
|---------------|--------|----------|----------------------------------------------|
| endpoint_addr | string | True     | URL of Casdoor.                              |
| client_id     | string | True     | Client ID in Casdoor.                        |
| client_secret | string | True     | Client secret in Casdoor.                    |
| callback_url  | string | True     | Callback URL used to receive state and code. |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

:::info IMPORTANT

`endpoint_addr` and `callback_url` should not end with '/'.

:::

:::info IMPORTANT

The `callback_url` must belong to the URI of your Route. See the code snippet below for an example configuration.

:::

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "uri": "/anything/*",
  "plugins": {
    "authz-casdoor": {
        "endpoint_addr":"http://localhost:8000",
        "callback_url":"http://localhost:9080/anything/callback",
        "client_id":"7ceb9b7fda4a9061ec1c",
        "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
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

## Example usage

Once you have enabled the Plugin, a new user visiting this Route would first be processed by the `authz-casdoor` Plugin. They would be redirected to the login page of Casdoor.

After successfully logging in, Casdoor will redirect this user to the `callback_url` with GET parameters `code` and `state` specified. The Plugin will also request for an access token and confirm whether the user is really logged in. This process is only done once and subsequent requests are left uninterrupted.

Once this is done, the user is redirected to the original URL they wanted to visit.

## Delete Plugin

To remove the `authz-casdoor` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```
