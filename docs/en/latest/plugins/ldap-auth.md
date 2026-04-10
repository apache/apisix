---
title: ldap-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - LDAP Authentication
  - ldap-auth
description: This document contains information about the Apache APISIX ldap-auth Plugin.
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

The `ldap-auth` Plugin can be used to add LDAP authentication to a Route or a Service.

This Plugin works with the Consumer object and the consumers of the API can authenticate with an LDAP server using [basic authentication](https://en.wikipedia.org/wiki/Basic_access_authentication).

This Plugin uses [lua-resty-ldap](https://github.com/api7/lua-resty-ldap) for connecting with an LDAP server.

## Attributes

For Consumer:

| Name    | Type   | Required | Description                                                                      |
| ------- | ------ | -------- | -------------------------------------------------------------------------------- |
| user_dn | string | True     | User dn of the LDAP client. For example, `cn=user01,ou=users,dc=example,dc=org`. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource. |

For Route:

| Name     | Type    | Required | Default | Description                                                            |
|----------|---------|----------|---------|------------------------------------------------------------------------|
| base_dn  | string  | True     |         | Base dn of the LDAP server. For example, `ou=users,dc=example,dc=org`. |
| ldap_uri | string  | True     |         | URI of the LDAP server.                                                |
| use_tls  | boolean | False    | `false` | If set to `true` uses TLS.                                             |
| tls_verify| boolean  | False     | `false`        | Whether to verify the server certificate when `use_tls` is enabled; If set to `true`, you must set `ssl_trusted_certificate` in `config.yaml`, and make sure the host of `ldap_uri` matches the host in server certificate. |
| uid      | string  | False    | `cn`    | uid attribute.                                                         |
| realm    | string  | False    | ldap    | The realm to include in the `WWW-Authenticate` header when authentication fails.                 |

## Enable plugin

First, you have to create a Consumer and enable the `ldap-auth` Plugin on it:

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
        "ldap-auth": {
            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
        }
    }
}'
```

Now you can enable the Plugin on a specific Route or a Service as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "ldap-auth": {
            "base_dn": "ou=users,dc=example,dc=org",
            "ldap_uri": "localhost:1389",
            "uid": "cn"
        },
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

After configuring the Plugin as mentioned above, clients can make requests with authorization to access the API:

```shell
curl -i -uuser01:password1 http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 OK
...
hello, world
```

If an authorization header is missing or invalid, the request is denied:

```shell
curl -i http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

```shell
curl -i -uuser:password1 http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

```shell
curl -i -uuser01:passwordfalse http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

## Delete Plugin

To remove the `ldap-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
