---
title: authz-casbin
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Authz Casbin
  - authz-casbin
description: This document contains information about the Apache APISIX authz-casbin Plugin.
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

The `authz-casbin` Plugin is an authorization Plugin based on [Lua Casbin](https://github.com/casbin/lua-casbin/). This Plugin supports powerful authorization scenarios based on various [access control models](https://casbin.org/docs/en/supported-models).

## Attributes

| Name        | Type   | Required | Description                                                                            |
|-------------|--------|----------|----------------------------------------------------------------------------------------|
| model_path  | string | True     | Path of the Casbin model configuration file.                                           |
| policy_path | string | True     | Path of the Casbin policy file.                                                        |
| model       | string | True     | Casbin model configuration in text format.                                             |
| policy      | string | True     | Casbin policy in text format.                                                          |
| username    | string | True     | Header in the request that will be used in the request to pass the username (subject). |

:::note

You must either specify the `model_path`, `policy_path`, and the `username` attributes or specify the `model`, `policy` and the `username` attributes in the Plugin configuration for it to be valid.

If you wish to use a global Casbin configuration, you can first specify `model` and `policy` attributes in the Plugin metadata and only the `username` attribute in the Plugin configuration. All Routes will use the Plugin configuration this way.

:::

## Metadata

| Name   | Type   | Required | Description                                |
|--------|--------|----------|--------------------------------------------|
| model  | string | True     | Casbin model configuration in text format. |
| policy | string | True     | Casbin policy in text format.              |

## Enable Plugin

You can enable the Plugin on a Route by either using the model/policy file paths or using the model/policy text in Plugin configuration/metadata.

### By using model/policy file paths

The example below shows setting up Casbin authentication from your model/policy configuration file:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "model_path": "/path/to/model.conf",
            "policy_path": "/path/to/policy.csv",
            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

### By using model/policy text in Plugin configuration

The example below shows setting up Casbin authentication from your model/policy text in your Plugin configuration:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "model": "[request_definition]
            r = sub, obj, act

            [policy_definition]
            p = sub, obj, act

            [role_definition]
            g = _, _

            [policy_effect]
            e = some(where (p.eft == allow))

            [matchers]
            m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

            "policy": "p, *, /, GET
            p, admin, *, *
            g, alice, admin",

            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

### By using model/policy text in Plugin metadata

First, you need to send a `PUT` request to the Admin API to add the `model` and `policy` text to the Plugin metadata.

All Routes configured this way will use a single Casbin enforcer with the configured Plugin metadata. You can also update the model/policy in this way and the Plugin will automatically update to the new configuration.

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/authz-casbin -H "X-API-KEY: $admin_key" -i -X PUT -d '
{
"model": "[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

"policy": "p, *, /, GET
p, admin, *, *
g, alice, admin"
}'
```

Once you have updated the Plugin metadata, you can add the Plugin to a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "authz-casbin": {
            "username": "user"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'
```

:::note

The Plugin Route configuration has a higher precedence than the Plugin metadata configuration. If the model/policy configuration is present in the Plugin Route configuration, it is used instead of the metadata configuration.

:::

## Example usage

We define the example model as:

```conf
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)
```

And the example policy as:

```conf
p, *, /, GET
p, admin, *, *
g, alice, admin
```

See [examples](https://github.com/casbin/lua-casbin/tree/master/examples) for more policy and model configurations.

The above configuration will let anyone access the homepage (`/`) using a `GET` request while only users with admin permissions can access other pages and use other request methods.

So if we make a get request to the homepage:

```shell
curl -i http://127.0.0.1:9080/ -X GET
```

But if an unauthorized user tries to access any other page, they will get a 403 error:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: bob' -X GET
HTTP/1.1 403 Forbidden
```

And only users with admin privileges can access the endpoints:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: alice' -X GET
```

## Delete Plugin

To remove the `authz-casbin` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
