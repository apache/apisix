---
title: multi-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Multi Auth
  - multi-auth
description: This document contains information about the Apache APISIX multi-auth Plugin.
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

The `multi-auth` Plugin is used to add multiple authentication methods to a Route or a Service. It supports plugins of type 'auth'. You can combine different authentication methods using `multi-auth` plugin.

This plugin provides a flexible authentication mechanism by iterating through the list of authentication plugins specified in the `auth_plugins` attribute. It allows multiple consumers to share the same route while using different authentication methods. For example, one consumer can authenticate using basic authentication, while another consumer can authenticate using JWT.

## Attributes

For Route:

| Name         | Type  | Required | Default | Description                                                           |
|--------------|-------|----------|---------|-----------------------------------------------------------------------|
| auth_plugins | array | True     | -       | Add supporting auth plugins configuration. expects at least 2 plugins |

## Enable Plugin

To enable the Plugin, you have to create two or more Consumer objects with different authentication configurations:

First create a Consumer using basic authentication:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo1",
    "plugins": {
        "basic-auth": {
            "username": "foo1",
            "password": "bar1"
        }
    }
}'
```

Then create a Consumer using key authentication:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo2",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

Once you have created Consumer objects, you can then configure a Route or a Service to authenticate requests:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "multi-auth":{
         "auth_plugins":[
            {
               "basic-auth":{ }
            },
            {
               "key-auth":{
                  "query":"apikey",
                  "hide_credentials":true,
                  "header":"apikey"
               }
            }
         ]
      }
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

Send a request with `basic-auth` credentials:

```shell
curl -i -ufoo1:bar1 http://127.0.0.1:9080/hello
```

Send a request with `key-auth` credentials:

```shell
curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -i
```

```
HTTP/1.1 200 OK
...
hello, world
```

If the request is not authorized, an `401 Unauthorized` error will be thrown:

```json
{"message":"Authorization Failed"}
```

## Delete Plugin

To remove the `multi-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
