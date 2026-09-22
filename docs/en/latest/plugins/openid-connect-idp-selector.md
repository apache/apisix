---
title: openid-connect-idp-selector
keywords:
  - Apache APISIX
  - API Gateway
  - OpenID Connect
  - OIDC
  - openid-connect-idp-selector
description: The openid-connect-idp-selector Plugin selects a per-request openid-connect IdP configuration (discovery/client_id/client_secret), so a single Route can serve multiple OpenID Connect realms, tenants, or domains without hard-coding provider-specific routing logic.
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

The `openid-connect-idp-selector` Plugin selects a named [`openid-connect`](./openid-connect.md) IdP configuration for a request, based on matching a value against a list of configured entries. It is meant to run at a higher priority than `openid-connect` on the same Route, so that a single Route can serve multiple IdP configurations (e.g. multiple realms, tenants, or domains) without hard-coding any provider-specific routing logic into `openid-connect` itself.

This Plugin does not perform any authentication on its own — it only selects which `discovery`, `client_id`, and `client_secret` values `openid-connect` should use for the current request, by exposing them as the `oidc_discovery`, `oidc_client_id`, and `oidc_client_secret` request-context variables. `openid-connect`'s corresponding fields must reference these with `${var}` templates (see [Selecting an IdP configuration per request](./openid-connect.md#selecting-an-idp-configuration-per-request)).

The value to match is the `iss` claim of the bearer token on the incoming `Authorization` header, decoded without verifying its signature — real signature verification still happens downstream in `openid-connect`, against whichever config gets selected. Because this needs a bearer token to already be on the request, it only matches once a client is calling in with a token; it cannot select a config for the first, unauthenticated request of an interactive browser login (`bearer_only: false`) flow — use it with `bearer_only: true` Routes.

## Attributes

| Name | Type | Required | Description |
|------|------|----------|-------------|
| configs | array | True | Candidate IdP configs. The first entry whose `key` equals the bearer token's `iss` claim is selected. |
| configs[].key | string | True | Issuer URL to match against the token's `iss` claim. |
| configs[].discovery | string | True | Discovery URL for this entry. |
| configs[].client_id | string | True | Client ID for this entry. |
| configs[].client_secret | string | True | Client secret for this entry. Stored encrypted at rest, like `openid-connect`'s own `client_secret`. |

If the token's issuer does not match any `configs` entry (including when there is no bearer token at all), this Plugin sets nothing, and `openid-connect` fails closed with a `500` response since its own `${var}` templates will resolve empty.

`configs[].key` acts as a whitelist: only an issuer your Route admin explicitly configured can ever cause a config to be selected.

## Enable the Plugin

Add both Plugins to a Route, with `openid-connect-idp-selector` supplying the values `openid-connect`'s templates reference — see the [Example](#example) below for the full configuration.

## Example

```json
{
  "plugins": {
    "openid-connect-idp-selector": {
      "configs": [
        {
          "key": "https://idp-acme.example.com/realms/acme",
          "discovery": "https://idp-acme.example.com/realms/acme/.well-known/openid-configuration",
          "client_id": "acme-client",
          "client_secret": "acme-secret"
        },
        {
          "key": "https://idp-globex.example.com/realms/globex",
          "discovery": "https://idp-globex.example.com/realms/globex/.well-known/openid-configuration",
          "client_id": "globex-client",
          "client_secret": "globex-secret"
        }
      ]
    },
    "openid-connect": {
      "discovery": "${oidc_discovery}",
      "client_id": "${oidc_client_id}",
      "client_secret": "${oidc_client_secret}",
      "bearer_only": true
    }
  }
}
```
