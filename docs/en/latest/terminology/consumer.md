---
title: Consumer
keywords:
  - Apache APISIX
  - API Gateway
  - APISIX Consumer
  - Consumer
description: This article describes the role of the Apache APISIX Consumer object and how to use the Consumer.
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

In APISIX, a **Consumer** represents a user, application, or host that sends requests through the gateway. Consumers are typically used with authentication plugins, which identify a Consumer from request credentials and make its plugin configuration available while APISIX processes the request.

![consumer-who](../../../assets/images/consumer-who.png)

Consumers can carry plugin configuration and can reference a [Consumer Group](./consumer-group.md) for shared plugin configuration. When the same plugin is configured in more than one local object, APISIX merges those configurations according to the [plugin merging precedence](./plugin.md#plugins-merging-precedence).

### Configuration options

The fields for defining a Consumer are defined as below.

| Field      | Required | Description |
| ---------- | -------- | ----------- |
| `username` | True | Unique name of the Consumer. |
| `desc` | False | Description of the Consumer. |
| `labels` | False | Labels attached to the Consumer. |
| `group_id` | False | ID of the Consumer Group whose plugins are merged with the Consumer's plugins. |
| `plugins` | False | Plugin configuration for the Consumer. See [Plugins](./plugin.md). |

## Identifying a Consumer

The process of identifying a Consumer in APISIX works as follows:

1. An authentication plugin, such as [key-auth](../plugins/key-auth.md) or [jwt-auth](../plugins/jwt-auth.md), validates the request credentials.
2. The plugin identifies the Consumer by its unique `username`.
3. APISIX merges the Consumer and Consumer Group plugin configuration with the plugin configuration from the matched Route, Plugin Config, and Service.

Consumers are useful when different applications or users request the same API and require different plugin configuration, such as rate limits or access controls. A Consumer does not hold an Upstream configuration.

Authentication plugins enabled in APISIX can be configured on a Consumer. Examples include `basic-auth`, `hmac-auth`, `jwt-auth`, `key-auth`, `ldap-auth`, and `wolf-rbac`.

Refer to the documentation for the [key-auth](../plugins/key-auth.md) authentication Plugin to further understand the concept of a Consumer.

:::note

For more information about the Consumer object, you can refer to the [Admin API Consumer](../admin-api.md#consumer) object resource introduction.

:::

## Example

The example below shows how you can enable a Plugin for a specific Consumer.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. Create a Consumer, specify the authentication plugin `key-auth`, and enable the specific plugin `limit-count`.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack",
        "plugins": {
            "key-auth": {
                "key": "auth-one"
            },
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

2. Create a Router, set routing rules and enable plugin configuration.

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

3. Send a test request, the first two return to normal, did not reach the speed limit threshold.

    ```shell
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
    ```

    The third test returns `503` and the request is restricted.

    ```shell
    HTTP/1.1 503 Service Temporarily Unavailable
    ...
    ```

We can use the [consumer-restriction](../plugins/consumer-restriction.md) Plugin to restrict our user "Jack" from accessing the API.

1. Add Jack to the blacklist.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {},
            "consumer-restriction": {
                "blacklist": [
                    "jack"
                ]
            }
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

2. Repeated tests, all return `403`; Jack is forbidden to access this API.

    ```shell
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
    ```

    ```shell
    HTTP/1.1 403
    ...
    ```
