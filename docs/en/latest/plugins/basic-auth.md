---
title: basic-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Basic Auth
  - basic-auth
description: This document contains information about the Apache APISIX basic-auth Plugin.
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

The `basic-auth` Plugin is used to add [basic access authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) to a Route or a Service.

This works well with a [Consumer](../terminology/consumer.md). Consumers of the API can then add their key to the header to authenticate their requests.

## Attributes

For Consumer:

| Name     | Type   | Required | Description                                                                                                            |
|----------|--------|----------|------------------------------------------------------------------------------------------------------------------------|
| username | string | True     | Unique username for a Consumer. If multiple Consumers use the same `username`, a request matching exception is raised. |
| password | string | True     | Password of the user. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.                      |

NOTE: `encrypt_fields = {"password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

For Route:

| Name             | Type    | Required | Default | Description                                                            |
|------------------|---------|----------|---------|------------------------------------------------------------------------|
| hide_credentials | boolean | False    | false   | Set to true will not pass the authorization request headers to the Upstream. |

## Enable Plugin

To enable the Plugin, you have to create a Consumer object with the authentication configuration:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "basic-auth": {
            "username": "foo",
            "password": "bar"
        }
    }
}'
```

You can also use the [APISIX Dashboard](/docs/dashboard/USER_GUIDE) to complete the operation through a web UI.

<!--
![auth-1](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/basic-auth-1.png)

![auth-2](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/basic-auth-2.png)
-->

Once you have created a Consumer object, you can then configure a Route or a Service to authenticate requests:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "basic-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Example usage

After you have configured the Plugin as mentioned above, you can make a request to the Route as shown below:

```shell
curl -i -ufoo:bar http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

If the request is not authorized, an error will be thrown:

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

And if the user or password is not valid:

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

## Delete Plugin

To remove the `jwt-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
