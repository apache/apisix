---
title: openid-connect
keywords:
  - APISIX
  - API Gateway
  - OpenID Connect
  - OIDC
description: OpenID Connect allows the client to obtain user information from the identity providers, such as Keycloak, Ory Hydra, Okta, Auth0, etc. API Gateway APISIX supports to integrate with the above identity providers to protect your APIs.
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

[OpenID Connect](https://openid.net/connect/) (OIDC) is an authentication protocol based on the OAuth 2.0. It allows the client to obtain user information from the identity provider (IdP), e.g., Keycloak, Ory Hydra, Okta, Auth0, etc. API Gateway Apache APISIX supports to integrate with the above identity providers to protect your APIs.

## Attributes

| Name                                 | Type    | Required | Default               | Valid values | Description                                                                                                              |
|--------------------------------------|---------|----------|-----------------------|--------------|--------------------------------------------------------------------------------------------------------------------------|
| client_id                            | string  | True     |                       |              | OAuth client ID.                                                                                                         |
| client_secret                        | string  | True     |                       |              | OAuth client secret.                                                                                                     |
| discovery                            | string  | True     |                       |              | Discovery endpoint URL of the identity server.                                                                           |
| scope                                | string  | False    | "openid"              |              | Scope used for authentication.                                                                                           |
| realm                                | string  | False    | "apisix"              |              | Realm used for authentication.                                                                                           |
| bearer_only                          | boolean | False    | false                 |              | When set to `true`, APISIX will only check if the authorization header in the request matches a bearer token.           |
| logout_path                          | string  | False    | "/logout"             |              | Path for logging out.                                                                                                    |
| post_logout_redirect_uri             | string  | False    |                       |              | URL to redirect to after logging out.                                                                                    |
| redirect_uri                         | string  | False    | "ngx.var.request_uri" |              | URI to which the identity provider redirects back to.                                                                    |
| timeout                              | integer | False    | 3                     | [1,...]      | Request timeout time in seconds.                                                                                         |
| ssl_verify                           | boolean | False    | false                 |              | When set to true, verifies the identity provider's SSL certificates.                                                     |
| introspection_endpoint               | string  | False    |                       |              | URL of the token verification endpoint of the identity server.                                                           |
| introspection_endpoint_auth_method   | string  | False    | "client_secret_basic" |              | Authentication method name for token introspection.                                                                      |
| token_endpoint_auth_method           | string  | False    |                       |              | Authentication method name for token endpoint. The default will get the first supported method specified by the OP.      |
| public_key                           | string  | False    |                       |              | Public key to verify the token.                                                                                          |
| use_jwks                             | boolean | False    | false                 |              | When set to `true`, uses the JWKS endpoint of the identity server to verify the token.                                   |
| use_pkce                             | boolean | False    | false                 |              | when set to `true`, the "Proof Key for Code Exchange" as defined in RFC 7636 will be used.   |
| token_signing_alg_values_expected    | string  | False    |                       |              | Algorithm used for signing the authentication token.                                                                     |
| set_access_token_header              | boolean | False    | true                  |              | When set to true, sets the access token in a request header.                                                             |
| access_token_in_authorization_header | boolean | False    | false                 |              | When set to true, sets the access token in the `Authorization` header. Otherwise, set the `X-Access-Token` header.       |
| set_id_token_header                  | boolean | False    | true                  |              | When set to true and the ID token is available, sets the ID token in the `X-ID-Token` request header.                    |
| set_userinfo_header                  | boolean | False    | true                  |              | When set to true and the UserInfo object is available, sets it in the `X-Userinfo` request header.                       |
| set_refresh_token_header             | boolean | False    | false                 |              | When set to true and a refresh token object is available, sets it in the `X-Refresh-Token` request header.               |
| session                              | object  | False    |                       |              | When bearer_only is set to false, openid-connect will use Authorization Code flow to authenticate on the IDP, so you need to set the session-related configuration. |
| session.secret                       | string  | True     | Automatic generation  | 16 or more characters | The key used for session encrypt and HMAC operation. |
| unauth_action                        | string  | False    | "auth"                |              | Specify the response type on unauthenticated requests. "auth" redirects to identity provider, "deny" results in a 401 response, "pass" will allow the request without authentication. |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Scenarios

:::tip

Tutorial: [Use Keycloak with API Gateway to secure APIs](https://apisix.apache.org/blog/2022/07/06/use-keycloak-with-api-gateway-to-secure-apis/)

:::

This plugin offers two scenorios:

1. Authentication between Services: Set `bearer_only` to `true` and configure the `introspection_endpoint` or `public_key` attribute. In this scenario, APISIX will reject requests without a token or invalid token in the request header.

2. Authentication between Browser and Identity Providers: Set `bearer_only` to `false.` After successful authentication, this plugin can obtain and manage the token in the cookie, and subsequent requests will use the token. In this mode, the user session will be stored in the browser as a cookie and this data is encrypted, so you have to set a key for encryption via `session.secret`.

### Token introspection

[Token introspection](https://www.oauth.com/oauth2-servers/token-introspection-endpoint/) validates a request by verifying the token with an OAuth 2.0 authorization server.

You should first create a trusted client in the identity server and generate a valid JWT token for introspection.

The image below shows an example token introspection flow via a Gateway:

![token introspection](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/oauth-1.png)

The example below shows how you can enable the Plugin on Route. The Rouet below will protect the Upstream by introspecting the token provided in the request header:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins":{
    "openid-connect":{
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "introspection_endpoint": "${INTROSPECTION_ENDPOINT}",
      "bearer_only": true,
      "realm": "master",
      "introspection_endpoint_auth_method": "client_secret_basic"
    }
  },
  "upstream":{
    "type": "roundrobin",
    "nodes":{
      "httpbin.org:443":1
    }
  }
}'
```

Now, to access the Route:

```bash
curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H "Authorization: Bearer {JWT_TOKEN}"
```

In this example, the Plugin enforces that the access token and the Userinfo object be set in the request headers.

When the OAuth 2.0 authorization server returns an expire time with the token, it is cached in APISIX until expiry. For more details, read:

1. [lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc)'s documentation and source code.
2. `exp` field in the RFC's [Introspection Response](https://tools.ietf.org/html/rfc7662#section-2.2) section.

### Introspecting with public key

You can also provide the public key of the JWT token for verification. If you have provided a public key and a token introspection endpoint, the public key workflow will be executed instead of verification through an identity server. This is useful if you want to reduce network calls and speedup the process.

The example below shows how you can add public key introspection to a Route:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins":{
    "openid-connect":{
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "bearer_only": true,
      "realm": "master",
      "token_signing_alg_values_expected": "RS256",
      "public_key": "-----BEGIN PUBLIC KEY-----
      {public_key}
      -----END PUBLIC KEY-----"
    }
  },
  "upstream":{
    "type": "roundrobin",
    "nodes":{
      "httpbin.org:443":1
    }
  }
}'
```

In this example, the Plugin can only enforce that the access token should be set in the request headers.

### Authentication through OIDC Relying Party flow

When an incoming request does not contain an access token in its header nor in an appropriate session cookie, the Plugin can act as an OIDC Relying Party and redirect to the authorization endpoint of the identity provider to go through the [OIDC authorization code flow](https://openid.net/specs/openid-connect-core-1_0.html#CodeFlowAuth).

Once the user has authenticated with the identity provider, the Plugin will obtain and manage the access token and further interaction with the identity provider. The access token will be stored in a session cookie.

The example below adds the Plugin with this mode of operation to the Route:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins": {
    "openid-connect": {
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "bearer_only": false,
      "realm": "master"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:443": 1
    }
  }
}'
```

In this example, the Plugin can enforce that the access token, the ID token, and the UserInfo object to be set in the request headers.

## Troubleshooting

1. If APISIX cannot resolve/connect to the identity provider (e.g., Okta, Keycloak, Authing), check/modify the DNS settings in your configuration file (`conf/config.yaml`).

2. If you encounter the error `the error request to the redirect_uri path, but there's no session state found,` please confirm whether the currently accessed URL carries `code` and `state,` and do not directly access `redirect_uri.`

2. If you encounter the error `the error request to the redirect_uri path, but there's no session state found`, please check the `redirect_uri` attribute : APISIX will initiate an authentication request to the identity provider, after the authentication service completes the authentication and authorization logic, it will redirect to the address configured by `redirect_uri` (e.g., `http://127.0.0.1:9080/callback`) with ID Token and AccessToken, and then enter APISIX again and complete the function of token exchange in OIDC logic. The `redirect_uri` attribute needs to meet the following conditions:

- `redirect_uri` needs to be captured by the route where the current APISIX is located. For example, the `uri` of the current route is `/api/v1/*`, `redirect_uri` can be filled in as `/api/v1/callback`;
- `scheme` and `host` of `redirect_uri` (`scheme:host`) are the values required to access APISIX from the perspective of the identity provider.
