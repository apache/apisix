---
title: saml-auth
keywords:
  - APISIX
  - Plugin
  - SAML AUTH
  - saml-auth
description: This document contains information about the Apache APISIX saml-auth Plugin.
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

The `saml-auth` Plugin can be used to access SAML (Security Assertion Markup Language 2.0) IdP (Identity Provider)
to do authentication, from the SP (service provider) perspective.

## Attributes

| Name      | Type | Required      | Description |
| ----------- | ----------- | ----------- | ----------- |
| `sp_issuer`      | string       | True      | SP name to access IdP.       |
| `idp_uri`      | string       | True      | URI of IdP.       |
| `idp_cert`      | string       | True      | IdP Certificate, used to verify saml response.       |
| `login_callback_uri`      | string       | True      | redirect uri used to callback the SP from IdP after login.       |
| `logout_uri`      | string       | True      | logout uri to trigger logout.       |
| `logout_callback_uri`      | string       | True      | redirect uri used to callback the SP from IdP after logout.       |
| `logout_redirect_uri`      | string       | True      | redirect uri after successful logout.       |
| `sp_cert`      | string       | True      | SP Certificate, used to sign the saml request.       |
| `sp_private_key`      | string       | True      | SP private key.       |

## Enabling the Plugin

You can enable the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_saml_auth -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {
          "saml-auth": {
            "idp_cert": "-----BEGIN CERTIFICATE-----\n...\n...\n-----END CERTIFICATE-----",
            "login_callback_uri": "/anything/login_callback",
            "sp_private_key": "-----BEGIN PRIVATE KEY-----\n...\n...\n-----END PRIVATE KEY-----",
            "logout_callback_uri": "/anything/logout_callback",
            "logout_uri": "/anything/logout",
            "logout_redirect_uri": "/anything/logout_ok",
            "sp_cert": "-----BEGIN CERTIFICATE-----\n...\n...\n-----END CERTIFICATE-----",
            "sp_issuer": "sp",
            "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/saml"
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

Once you have enabled the Plugin, a new user visiting this Route would first be processed by the `saml-auth` Plugin.
If no login session exists, the user would be redirected to the login page of `idp_uri`.

After successfully logging in from IdP, IdP will redirect this user to the `login_callback_uri` with
GET parameters SAML Assertion specified. If the assertion gets verified, the login session would be created.

This process is only done once and subsequent requests are left uninterrupted.
Once this is done, the user is redirected to the original URL they wanted to visit.

Later, the user could visit `logout_uri` to start logout process. The user would be redirected to `idp_uri` to do logout.

After successfully logging out from IdP, the user would be redirected to `logout_callback_uri` and clear the session there.

Finally, the user would be redirected to `logout_redirect_uri`.

Note that, `login_callback_uri`, `logout_callback_uri`, `logout_uri` and `logout_redirect_uri` should be
either full qualified address (e.g. `http://127.0.0.1:9080/anything/logout`),
or path only (e.g. `/logout`), but it is recommended to be path only to keep consistent.

These uris need to be captured by the route where the current APISIX is located.
For example, if the `uri` of the current route is `/api/v1/*`, `login_callback_uri` can be filled in as `/api/v1/login_callback`.

## Disable Plugin

To disable the `saml-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_saml_auth  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
