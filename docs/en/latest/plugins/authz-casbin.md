---
title: authz-casbin
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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**Metadata**](#metadata)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)
- [**Examples**](#examples)

## Name

`authz-casbin` is an authorization plugin based on [Lua Casbin](https://github.com/casbin/lua-casbin/). This plugin supports powerful authorization scenarios based on various access control models.

For detailed documentation on how to create model and policy, refer [Casbin](https://casbin.org/docs/en/supported-models).

## Attributes

| Name        | Type   | Requirement | Default | Valid | Description                                                  |
| ----------- | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| model_path  | string | required    |         |       | The path of the Casbin model configuration file.             |
| policy_path | string | required    |         |       | The path of the Casbin policy file.                          |
| model       | string | required    |         |       | The Casbin model configuration in text format.               |
| policy      | string | required    |         |       | The Casbin policy in text format.                            |
| username    | string | required    |         |       | The header you will be using in request to pass the username (subject). |

**NOTE**: You must either specify `model_path`, `policy_path` and `username` in plugin config or specify `model`, `policy` and `username` in the plugin config for the configuration to be valid. Or if you wish to use a global Casbin configuration, you can first specify `model` and `policy` in the plugin metadata and only `username` in the plugin configuration, all routes will use the plugin metadata configuration in this way.

## Metadata

| Name        | Type   | Requirement | Default | Valid | Description                                                            |
| ----------- | ------ | ----------- | ------- | ----- | ---------------------------------------------------------------------- |
| model       | string | required    |         |       | The Casbin model configuration in text format.                         |
| policy      | string | required    |         |       | The Casbin policy in text format.                                      |

## How To Enable

You can enable the plugin on any route either by using the model/policy file paths or directly using the model/policy text.

### By using file paths

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

This will create a Casbin enforcer from the model and policy files at your first request.

### By using model/policy text

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

This will create a Casbin enforcer from the model and policy text at your first request.

### By using model/policy text using plugin metadata

First, send a `PUT` request to add the model and policy text to the plugin's metadata using the Admin API. All routes configured in this way will use a single Casbin enforcer with plugin metadata configuration. You can also update the model/policy this way, the plugin will automatically update itself with the updated configuration.

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/authz-casbin -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
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

Then add this plugin on a route by sending the following request. Note, there is no requirement for model/policy now.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

**NOTE**: The plugin route configuration has a higher precedence than the plugin metadata configuration. Hence if the model/policy configuration is present in the plugin route config, the plugin will use that instead of the metadata config.

## Test Plugin

We defined the example model as:

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

This means that anyone can access the homepage (`/`) using `GET` request method while only users with admin permissions can access other pages and use other request methods.

For example, here anyone can access the homepage with the GET request method and the request proceeds normally:

```shell
curl -i http://127.0.0.1:9080/ -X GET
```

If some unauthorized user `bob` tries to access any other page, they will get a 403 error:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: bob' -X GET
HTTP/1.1 403 Forbidden
```

But someone with admin permissions like `alice`can access it:

```shell
curl -i http://127.0.0.1:9080/res -H 'user: alice' -X GET
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `authz-casbin` plugin.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Examples

Checkout examples for model and policy conguration [here](https://github.com/casbin/lua-casbin/tree/master/examples).
