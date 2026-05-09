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
| login_callback_uri | string | True | | | | SP's Assertion Consumer Service (ACS) URL. The IdP posts SAML responses to this URL after authentication. Must be registered with the IdP. |
| logout_uri | string | True | | | | SP's Single Logout (SLO) endpoint. Requests to this URI initiate the logout flow. |
| logout_callback_uri | string | True | | | | SP's SLO callback URL. The IdP sends logout responses to this URL. Must be registered with the IdP. |
| logout_redirect_uri | string | True | | | | URL to redirect users to after a successful logout. |
| sp_cert | string | True | | | | SP's X.509 certificate in PEM format. Used by the IdP to verify requests signed by the SP. |
| sp_private_key | string | True | Yes | | | SP's private key in PEM format, used to sign SAML requests. This field is encrypted at rest. |
| auth_protocol_binding_method | string | False | | `HTTP-Redirect` | `HTTP-Redirect`, `HTTP-POST` | SAML binding method for the authentication request. When set to `HTTP-POST`, the session cookie `SameSite` attribute is set to `None` and `Secure` is set to `true`. |
| secret | string | False | Yes | | 8–32 characters | Secret used for session key derivation. This field is encrypted at rest. |
| secret_fallbacks | array[string] | False | Yes | | Each item: 8–32 characters | List of previous secrets used during key rotation. Allows sessions encrypted with old secrets to remain valid. This field is encrypted at rest. |

## Prerequisites

Before configuring the `saml-auth` Plugin, you need to register APISIX as a Service Provider with your Identity Provider. The exact steps depend on your IdP; the following example uses [Keycloak](https://www.keycloak.org/).

### Set Up Keycloak

1. Log in to the Keycloak Admin Console.
2. Create or select a realm (for example, `myrealm`).
3. Navigate to **Clients** and click **Create client**.
4. Set **Client type** to `SAML`.
5. Set **Client ID** to match the `sp_issuer` value you will use in the Plugin configuration (for example, `https://sp.example.com`).
6. Under **Client** > **Settings**:
   - Set **Root URL** to `https://sp.example.com`.
   - Set **Valid redirect URIs** to include the `login_callback_uri` (for example, `https://sp.example.com/login/callback`).
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
        "login_callback_uri": "https://sp.example.com/login/callback",
        "logout_uri": "https://sp.example.com/logout",
        "logout_callback_uri": "https://sp.example.com/logout/callback",
        "logout_redirect_uri": "https://sp.example.com/logout/done",
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
