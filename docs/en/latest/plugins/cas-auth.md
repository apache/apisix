---
title: cas-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - CAS AUTH
  - cas-auth
description: This document contains information about the Apache APISIX cas-auth Plugin.
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

The `cas-auth` Plugin can be used to access CAS (Central Authentication Service 2.0) IdP (Identity Provider)
to do authentication, from the SP (service provider) perspective.

## Attributes

| Name      | Type | Required      | Description |
| ----------- | ----------- | ----------- | ----------- |
| `idp_uri`      | string       | True      | URI of IdP.       |
| `cas_callback_uri`      | string       | True      | redirect uri used to callback the SP from IdP after login or logout.       |
| `logout_uri`      | string       | True      | logout uri to trigger logout.       |

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/cas1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET", "POST"],
    "host" : "127.0.0.1",
    "uri": "/anything/*",
    "plugins": {
          "cas-auth": {
              "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/cas",
              "cas_callback_uri": "/anything/cas_callback",
              "logout_uri": "/anything/logout"
          }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'

```

## Configuration description

Once you have enabled the Plugin, a new user visiting this Route would first be processed by the `cas-auth` Plugin.
If no login session exists, the user would be redirected to the login page of `idp_uri`.

After successfully logging in from IdP, IdP will redirect this user to the `cas_callback_uri` with
GET parameters CAS ticket specified. If the ticket gets verified, the login session would be created.

This process is only done once and subsequent requests are left uninterrupted.
Once this is done, the user is redirected to the original URL they wanted to visit.

Later, the user could visit `logout_uri` to start logout process. The user would be redirected to `idp_uri` to do logout.

Note that, `cas_callback_uri` and `logout_uri` should be
either full qualified address (e.g. `http://127.0.0.1:9080/anything/logout`),
or path only (e.g. `/anything/logout`), but it is recommended to be path only to keep consistent.

These uris need to be captured by the route where the current APISIX is located.
For example, if the `uri` of the current route is `/api/v1/*`, `cas_callback_uri` can be filled in as `/api/v1/cas_callback`.

## Delete Plugin

To remove the `cas-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/cas1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET", "POST"],
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
