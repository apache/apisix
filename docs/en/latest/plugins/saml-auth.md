---
title: saml-auth
keywords:
  - Apache APISIX
  - API Gateway
  - SAML
  - SAML 2.0
  - SSO
  - Single Sign-On
description: The saml-auth Plugin enables SAML 2.0 authentication for API routes, integrating with external Identity Providers (IdP) such as Keycloak, Okta, and Azure Active Directory.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/saml-auth" />
</head>

## Description

The `saml-auth` Plugin enables [SAML 2.0](https://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html) (Security Assertion Markup Language) authentication for API routes. It acts as a SAML Service Provider (SP) and integrates with external Identity Providers (IdP) such as Keycloak, Okta, and Azure Active Directory to authenticate users before allowing access to upstream resources.

When a request arrives at a protected route, the Plugin checks for a valid SAML session. If no session exists, it redirects the user to the IdP for authentication. After the user authenticates at the IdP, the IdP posts a signed SAML assertion back to the SP's Assertion Consumer Service (ACS) URL. The Plugin validates the assertion and establishes a session for the user.

The Plugin supports:

- **HTTP-Redirect binding** (default) — SAML messages are transmitted as URL query parameters.
- **HTTP-POST binding** — SAML messages are transmitted as HTML form values.
- **Single Logout (SLO)** — logout requests can be initiated by the SP or the IdP.
- **Session key rotation** via `secret_fallbacks`.

Authenticated user data is stored in `ctx.external_user` and can be used by downstream authorization plugins such as `acl`.

## Attributes

| Name | Type | Required | Encrypted | Default | Valid Values | Description |
|------|------|----------|-----------|---------|--------------|-------------|
| sp_issuer | string | True | | | | Service Provider (SP) entity ID/issuer URI. Must match the SP entity ID registered with the IdP. |
| idp_uri | string | True | | | | Identity Provider SSO endpoint URL. This is the URL to which SAML authentication requests are sent. |
| idp_cert | string | True | | | | IdP's X.509 certificate in PEM format, used to verify signatures on SAML assertions. |
| login_callback_uri | string | True | | | | Request path of the SP's Assertion Consumer Service (ACS), such as `/login/callback`. The Plugin handles the IdP's login response on requests whose path equals this value. It is a path, so the externally visible absolute ACS URL is configured in `sp_acs_url`. |
| logout_uri | string | True | | | | Request path of the SP's Single Logout (SLO) endpoint, such as `/logout`. Requests to this path initiate the logout flow. |
| logout_callback_uri | string | True | | | | Request path of the SP's SLO callback, such as `/logout/callback`. The IdP sends logout requests and responses to this path. Must be registered with the IdP. |
| logout_redirect_uri | string | True | | | | URL to redirect users to after a successful logout. |
| sp_cert | string | True | | | | SP's X.509 certificate in PEM format. Used by the IdP to verify requests signed by the SP. |
| sp_private_key | string | True | Yes | | | SP's private key in PEM format, used to sign SAML requests. This field is encrypted at rest. |
| auth_protocol_binding_method | string | False | | `HTTP-Redirect` | `HTTP-Redirect`, `HTTP-POST` | SAML binding method for the authentication request. When set to `HTTP-POST`, the session cookie `SameSite` attribute is set to `None` and `Secure` is set to `true`. |
| secret | string | True | Yes | | 8–32 characters | Secret used for session key derivation. Must be identical on all APISIX nodes to ensure sessions are readable across workers and after reloads. This field is encrypted at rest. |
| secret_fallbacks | array[string] | False | Yes | | Each item: 8–32 characters | List of previous secrets used during key rotation. Allows sessions encrypted with old secrets to remain valid. This field is encrypted at rest. |
| idp_issuers | array[string] | False | | | | Issuers accepted on a login response. Every assertion in the response must name one of them. When unset, any issuer signed with `idp_cert` is accepted. An empty array accepts no issuer, so every login is refused. See [Issuer and audience](#issuer-and-audience). |
| sp_acs_url | string | False | | | Absolute `http://` or `https://` URL | Externally visible absolute URL of the SP's ACS, such as `https://sp.example.com/login/callback`. It is sent to the IdP in the authentication request, and the `Destination` and `Recipient` of the login response must equal it. When unset, it is built from the request's scheme, host, and `login_callback_uri`. See [ACS URL behind a proxy](#acs-url-behind-a-proxy). |
| sp_audiences | array[string] | False | | `sp_issuer` | | Audiences this SP accepts. An assertion carrying an `AudienceRestriction` must name one of them. When unset, only `sp_issuer` is accepted. |
| clock_skew | number | False | | `60` | >= 0 | Seconds of clock difference tolerated against the IdP when checking `NotBefore` and `NotOnOrAfter`. |
| replay_dict | string | False | | | Non-empty | Name of a declared `lua_shared_dict` that records accepted assertions, so that one assertion cannot log in twice on the same APISIX node. When unset, accepted assertions are not recorded. See [Assertion replay protection](#assertion-replay-protection). |
| replay_ttl | number | False | | `600` | >= 1 | Seconds to record an assertion whose acceptance has no expiry. Assertions with an expiry are recorded until they expire, plus `clock_skew`, for at most one day or `replay_ttl` when that is longer. Only used when `replay_dict` is set. |

## Prerequisites

Install `lua-resty-saml` on every APISIX node before enabling this Plugin:

```shell
luarocks install lua-resty-saml 0.2.6
```

`lua-resty-saml` builds native xmlsec bindings, so the build environment must provide the OpenSSL, libxml2, and libxslt development files required by LuaRocks.

Before configuring the `saml-auth` Plugin, you need to register APISIX as a Service Provider with your Identity Provider. The exact steps depend on your IdP; the following example uses [Keycloak](https://www.keycloak.org/).

### Set Up Keycloak

1. Log in to the Keycloak Admin Console.
2. Create or select a realm (for example, `myrealm`).
3. Navigate to **Clients** and click **Create client**.
4. Set **Client type** to `SAML`.
5. Set **Client ID** to match the `sp_issuer` value you will use in the Plugin configuration (for example, `https://sp.example.com`).
6. Under **Client** > **Settings**:
   - Set **Root URL** to `https://sp.example.com`.
   - Set **Valid redirect URIs** to include the absolute ACS URL, which is the `sp_acs_url` (for example, `https://sp.example.com/login/callback`).
   - Set **Master SAML Processing URL** to `https://sp.example.com/login/callback`.
7. Under **Client** > **Keys**, upload the SP certificate (`sp_cert`) and enable **Sign assertions**.
8. Export the IdP metadata to obtain the `idp_uri` (SSO URL) and `idp_cert` (signing certificate).
9. Create users in Keycloak that will be allowed to authenticate.

## Enable the Plugin

The following example creates a route protected by the `saml-auth` Plugin using a Keycloak IdP:

:::note

Replace the placeholder certificate and key values with your actual SP certificate, SP private key, and IdP certificate.

:::

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT \
  -d '{
    "uri": "/*",
    "plugins": {
      "saml-auth": {
        "sp_issuer": "https://sp.example.com",
        "idp_uri": "https://keycloak.example.com/realms/myrealm/protocol/saml",
        "idp_cert": "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
        "login_callback_uri": "/login/callback",
        "sp_acs_url": "https://sp.example.com/login/callback",
        "logout_uri": "/logout",
        "logout_callback_uri": "/logout/callback",
        "logout_redirect_uri": "https://sp.example.com/logout/done",
        "idp_issuers": ["https://keycloak.example.com/realms/myrealm"],
        "sp_audiences": ["https://sp.example.com"],
        "sp_cert": "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
        "sp_private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----",
        "auth_protocol_binding_method": "HTTP-Redirect",
        "secret": "my-session-secret"
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

## Response Validation

The Plugin passes the options below to `lua-resty-saml`, which checks every login response against them. All of them are optional, and a configuration that omits them keeps its existing behavior.

### Issuer and audience

`idp_cert` proves that a response was signed with the IdP's key, but a key may sign for several issuers, such as several realms of one IdP deployment. Set `idp_issuers` to the issuer, or entity ID, of the IdP you expect. For Keycloak it is `https://<keycloak-host>/realms/<realm>`. A response carrying an assertion from any other issuer is refused with `401`. Leaving `idp_issuers` unset accepts any issuer, while an empty array accepts none.

An IdP restricts each assertion to an audience, which is normally the SP's entity ID. The Plugin accepts an assertion whose `AudienceRestriction` names `sp_issuer`. Set `sp_audiences` when the IdP issues a different audience, and list every audience the SP accepts, since `sp_issuer` is no longer added once `sp_audiences` is set.

`clock_skew` sets how many seconds of clock difference between the APISIX node and the IdP are tolerated when checking the assertion's validity window. Keep APISIX nodes synchronized with NTP so the default is sufficient.

### ACS URL behind a proxy

The IdP sends the login response to an absolute ACS URL, and the response names that URL in its `Destination` and `Recipient`. The response is refused with `401` when they differ from the ACS URL the Plugin expects.

When `sp_acs_url` is unset, the Plugin builds the expected URL from the scheme and host of the request that reaches APISIX. That URL is wrong whenever APISIX sees a different scheme or host than the browser, for example when a load balancer terminates TLS and forwards plain HTTP, or rewrites the `Host` header. Every login is then refused. Set `sp_acs_url` to the URL the browser uses, which is the ACS URL registered with the IdP:

```json
{
  "login_callback_uri": "/login/callback",
  "sp_acs_url": "https://sp.example.com/login/callback"
}
```

`login_callback_uri` stays the request path that APISIX matches, and `sp_acs_url` is the absolute URL the IdP and the browser use. The path of `sp_acs_url` should resolve to `login_callback_uri` once the request reaches APISIX.

### Assertion replay protection

Set `replay_dict` to record the assertions each APISIX node accepts, so that presenting the same login response again is refused with `401`. Declare the shared dict in `conf/config.yaml` on every APISIX node:

```yaml
nginx_config:
  http:
    custom_lua_shared_dict:
      saml_replay: 10m
```

Then reference it from the Plugin:

```json
{
  "replay_dict": "saml_replay",
  "replay_ttl": 600
}
```

The Plugin does not create the shared dict. A route naming a shared dict that is not declared answers every request with `500` and logs `no lua_shared_dict named <name>`.

Consider the following when enabling replay protection:

- **The record is local to one node.** A `lua_shared_dict` is shared by the worker processes of one APISIX node only. When several APISIX nodes serve the same route, a response accepted by one node is not known to the others. On every node, `lua-resty-saml` still binds a response to the login request stored in the user's session, provided the IdP sends `InResponseTo`, which mainstream IdPs do.
- **Size the shared dict for the login rate.** Each accepted assertion holds an entry until it expires. For example, 10 logins per second with 10-minute assertions keep about 6,000 entries, which needs more than `1m`. When the shared dict is full, the assertion is accepted without being recorded and an error is logged.
- **A repeated submission is refused.** A browser that submits the same login response again, for example after going back in history, receives `401`. Opening the protected URL again starts a new login.

## Disable the Plugin

To disable the `saml-auth` Plugin, remove it from the route configuration:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT \
  -d '{
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
