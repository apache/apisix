---
title: openid-connect-consumer-selector
keywords:
  - Apache APISIX
  - API Gateway
  - OpenID Connect
  - OIDC
  - openid-connect-consumer-selector
description: The openid-connect-consumer-selector Plugin selects a per-request openid-connect IdP configuration (discovery/client_id/client_secret), so a single Route can serve multiple OpenID Connect realms, tenants, or domains without hard-coding provider-specific routing logic.
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

The `openid-connect-consumer-selector` Plugin selects a named [`openid-connect`](./openid-connect.md) IdP configuration for a request, based on matching a value against a list of configured entries. It is meant to run at a higher priority than `openid-connect` on the same Route, so that a single Route can serve multiple IdP configurations (e.g. multiple realms, tenants, or domains) without hard-coding any provider-specific routing logic into `openid-connect` itself.

This Plugin does not perform any authentication on its own — it only selects which `discovery`, `client_id`, and `client_secret` values `openid-connect` should use for the current request, by exposing them as the `oidc_discovery`, `oidc_client_id`, and `oidc_client_secret` request-context variables. `openid-connect`'s corresponding fields must reference these with `${var}` templates (see [Selecting an IdP configuration per request](./openid-connect.md#selecting-an-idp-configuration-per-request)).

The value to match is read from one of two sources, chosen with `match_source`:

- `var` (default): an arbitrary request-context variable, named by `match_var`.
- `token_iss`: the `iss` claim of the bearer token on the incoming `Authorization` header, decoded without verifying its signature — real signature verification still happens downstream in `openid-connect`, against whichever config gets selected. Because this mode needs a bearer token to already be on the request, it only matches once a client is calling in with a token; it cannot select a config for the first, unauthenticated request of an interactive browser login (`bearer_only: false`) flow.

## Attributes

| Name | Type | Required | Description |
|------|------|----------|-------------|
| match_source | string | False | `"var"` (default) or `"token_iss"` — see above. |
| match_var | string | Only when `match_source` is `"var"` | Name of the request-context variable to read (e.g. `http_x_tenant_id`) and match against each `configs` entry's `key`. |
| configs | array | True | Candidate IdP configs. The first entry whose `key` equals the resolved match value is selected. |
| configs[].key | string | True | Value to match against the resolved match value — e.g. a tenant id (`var` mode) or an issuer URL (`token_iss` mode). |
| configs[].discovery | string | True | Discovery URL for this entry. |
| configs[].client_id | string | True | Client ID for this entry. |
| configs[].client_secret | string | True | Client secret for this entry. Stored encrypted at rest, like `openid-connect`'s own `client_secret`. |

If the match value resolves to something that does not match any `configs` entry (including when it is absent or unreadable), this Plugin sets nothing, and `openid-connect` fails closed with a `500` response since its own `${var}` templates will resolve empty.

`configs[].key` acts as a whitelist: only a value your Route admin explicitly configured can ever cause a config to be selected, so this Plugin is safe to use with `match_var` sources an untrusted client can influence (e.g. a header). Do not template `openid-connect`'s `discovery` field directly off a client-controlled variable without going through this whitelist — an unvalidated `${var}`-templated `discovery` URL can be pointed at an arbitrary host (SSRF).

## Enable the Plugin

Add both Plugins to a Route, with `openid-connect-consumer-selector` supplying the values `openid-connect`'s templates reference — see the [Example](#example) below for the full configuration.

## Example

```json
{
  "plugins": {
    "openid-connect-consumer-selector": {
      "match_var": "http_x_tenant_id",
      "configs": [
        {
          "key": "acme",
          "discovery": "https://idp-acme.example.com/.well-known/openid-configuration",
          "client_id": "acme-client",
          "client_secret": "acme-secret"
        },
        {
          "key": "globex",
          "discovery": "https://idp-globex.example.com/.well-known/openid-configuration",
          "client_id": "globex-client",
          "client_secret": "globex-secret"
        }
      ]
    },
    "openid-connect": {
      "discovery": "${oidc_discovery}",
      "client_id": "${oidc_client_id}",
      "client_secret": "${oidc_client_secret}",
      "redirect_uri": "https://example.com/protected/.apisix/redirect",
      "session": {
        "secret": "some-strong-random-secret"
      }
    }
  }
}
```

Selecting by the bearer token's issuer instead, for a `bearer_only` Route — same route shape as above, `openid-connect-consumer-selector`'s config changed to:

```json
{
  "match_source": "token_iss",
  "configs": [
    {
      "key": "https://idp-acme.example.com/realms/acme",
      "discovery": "https://idp-acme.example.com/realms/acme/.well-known/openid-configuration",
      "client_id": "acme-client",
      "client_secret": "acme-secret"
    }
  ]
}
```

and `openid-connect` configured with `"bearer_only": true` instead of `session`.
