---
title: Credential
keywords:
  - APISIX
  - API Gateway
  - Consumer
  - Credential
description: This article describes what the Apache APISIX Credential object does and how to use it.
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

Credential is the object that holds the [Consumer](./consumer.md) credential configuration.
A Consumer can use multiple credentials of different types.
Credentials are used when you need to configure multiple credentials for a Consumer.

Currently, Credential can be configured with the authentication plugins `basic-auth`, `hmac-auth`, `jwt-auth`, and `key-auth`.

### Configuration options

The fields for defining a Credential are defined as below.

| Field      | Required | Description                                                                                             |
|---------|----------|---------------------------------------------------------------------------------------------------------|
| desc    | False    | Description of the Credential.                                                                          |
| labels  | False    | Labels of the Credential.                                                                               |
| plugins | False    | The plugin configuration corresponding to Credential. For more information, see [Plugins](./plugin.md). |

:::note

For more information about the Credential object, you can refer to the [Admin API Credential](../admin-api.md#credential) resource guide.

:::

## Example

[Consumer Example](./consumer.md#example) describes how to configure the auth plugin for Consumer and how to use it with other plugins.
In this example, the Consumer has only one credential of type key-auth.
Now suppose the user needs to configure multiple credentials for that Consumer, you can use Credential to support this.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. Create the Consumer without specifying the auth plug-in, but use Credential to configure the auth plugin later.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack"
    }'
    ```

2. Create 2 `key-auth` Credentials for the Consumer.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials/key-auth-one \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {
                "key": "auth-one"
            }
        }
    }'
    ```

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials/key-auth-two \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {
                "key": "auth-two"
            }
        }
    }'
    ```

3. Create a route and enable `key-auth` plugin on it.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {}
        },
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": 1
            },
            "type": "roundrobin"
        },
        "uri": "/hello"
    }'
    ```

4. Test.

    Test the request with the `auth-one` and `auth-two` keys, and they both respond correctly.

    ```shell
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-two' -I
    ```

    Enable the `limit-count` plugin for the Consumer.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack",
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

    Requesting the route more than 3 times in a row with each of the two keys, the test returns `503` and the request is restricted.
