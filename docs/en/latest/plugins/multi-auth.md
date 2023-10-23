---
title: basic-auth
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

The `multi-auth` Plugin is used to add multiple authentication methods to a Route or a Service. Plugins with type 'auth' are supported.

## Attributes

For Route:

| Name        | Type  | Required | Default | Description                                                                             |
|-------------|-------|----------|---------|-----------------------------------------------------------------------------------------|
| auth_plugin | array | True     | -       | Add supporting auth plugin configuration. |

## Enable Plugin

To enable the Plugin, you have to create a Consumer object with multiple authentication configurations:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "basic-auth": {
            "username": "foo",
            "password": "bar"
        },
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

You can also use the [APISIX Dashboard](/docs/dashboard/USER_GUIDE) to complete the operation through a web UI.

Once you have created a Consumer object, you can then configure a Route or a Service to authenticate requests:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

```shell
curl -i -ufoo:bar http://127.0.0.1:9080/hello
```

```shell
curl http://127.0.0.2:9080/hello -H 'apikey: auth-one' -i
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
{"message":"Authorization Failed"}
```

## Delete Plugin

To remove the `multi-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
