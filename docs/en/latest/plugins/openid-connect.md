---
title: openid-connect
keywords:
  - Apache APISIX
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

| Name                                 | Type     | Required | Default               | Valid values | Description                                                                                                                                                                                                                           |
|--------------------------------------|----------|----------|-----------------------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| client_id                            | string   | True     |                       |              | OAuth client ID.                                                                                                                                                                                                                      |
| client_secret                        | string   | True     |                       |              | OAuth client secret.                                                                                                                                                                                                                  |
| discovery                            | string   | True     |                       |              | Discovery endpoint URL of the identity server.                                                                                                                                                                                        |
| scope                                | string   | False    | "openid"              |              | OIDC scope that corresponds to information that should be returned about the authenticated user, also known as [claims](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims). The default value is `openid`, the required scope for OIDC to return a `sub` claim that uniquely identifies the authenticated user. Additional scopes can be appended and delimited by spaces, such as `openid email profile`.                                                                                                                                                                                                        |
| required_scopes                      | string[] | False    |                       |              | Array of strings. Used in conjunction with the introspection endpoint (when `bearer_only` is `true`). If present, the plugin will check if the token contains all required scopes. If not, 403 will be returned with an error message |
| realm                                | string   | False    | "apisix"              |              | Realm used for authentication.                                                                                                                                                                                                        |
| bearer_only                          | boolean  | False    | false                 |              | When set to `true`, APISIX will only check if the authorization header in the request matches a bearer token.                                                                                                                         |
| logout_path                          | string   | False    | "/logout"             |              | Path for logging out.                                                                                                                                                                                                                 |
| post_logout_redirect_uri             | string   | False    |                       |              | URL to redirect to after logging out. If the OIDC discovery endpoint does not provide an [`end_session_endpoint`](https://openid.net/specs/openid-connect-rpinitiated-1_0.html), the plugin internally redirects using the [`redirect_after_logout_uri`](https://github.com/zmartzone/lua-resty-openidc). Otherwise, it redirects using the [`post_logout_redirect_uri`](https://openid.net/specs/openid-connect-rpinitiated-1_0.html). |
| redirect_uri                         | string  | False    |                       |              | URI to which the identity provider redirects back to. If not configured, APISIX will append the `.apisix/redirect` suffix to determine the default `redirect_uri`. Note that the provider should be properly configured to allow such `redirect_uri` values. |
| timeout                              | integer  | False    | 3                     | [1,...]      | Request timeout time in seconds.                                                                                                                                                                                                      |
| ssl_verify                           | boolean  | False    | false                 |              | When set to true, verifies the identity provider's SSL certificates.                                                                                                                                                                  |
| introspection_endpoint               | string   | False    |                       |              | URL of the token verification endpoint of the identity server.                                                                                                                                                                        |
| introspection_endpoint_auth_method   | string   | False    | "client_secret_basic" |              | Authentication method name for token introspection.                                                                                                                                                                                   |
| token_endpoint_auth_method           | string   | False    |                       |              | Authentication method name for token endpoint. The default will get the first supported method specified by the OP.                                                                                                                   |
| public_key                           | string   | False    |                       |              | Public key to verify the token.                                                                                                                                                                                                       |
| use_jwks                             | boolean  | False    | false                 |              | When set to `true`, uses the JWKS endpoint of the identity server to verify the token.                                                                                                                                                |
| use_pkce                             | boolean  | False    | false                 |              | when set to `true`, the "Proof Key for Code Exchange" as defined in RFC 7636 will be used.                                                                                                                                            |
| token_signing_alg_values_expected    | string   | False    |                       |              | Algorithm used for signing the authentication token.                                                                                                                                                                                  |
| set_access_token_header              | boolean  | False    | true                  |              | When set to true, sets the access token in a request header. By default, the `X-Access-Token` header is used.                                                                                                                                                                         |
| access_token_in_authorization_header | boolean  | False    | false                 |              | When set to true and `set_access_token_header` is also true, sets the access token in the `Authorization` header.                                                                                                                    |
| set_id_token_header                  | boolean  | False    | true                  |              | When set to true and the ID token is available, sets the ID token in the `X-ID-Token` request header.                                                                                                                                 |
| set_userinfo_header                  | boolean  | False    | true                  |              | When set to true and the UserInfo object is available, sets it in the `X-Userinfo` request header.                                                                                                                                    |
| set_refresh_token_header             | boolean  | False    | false                 |              | When set to true and a refresh token object is available, sets it in the `X-Refresh-Token` request header.                                                                                                                            |
| session                              | object   | False    |                       |              | When bearer_only is set to false, openid-connect will use Authorization Code flow to authenticate on the IDP, so you need to set the session-related configuration.                                                                   |
| session.secret                       | string   | True     | Automatic generation  | 16 or more characters | The key used for session encrypt and HMAC operation.                                                                                                                                                                                  |
| session.cookie                       | object   | False    |                       |             |                                                                                                                                                                                  |
| session.cookie.lifetime              | integer   | False    | 3600                  |             | Cookie lifetime in seconds. |
| unauth_action                        | string   | False    | "auth"                |  ["auth","deny","pass"]            | Specify the response type on unauthenticated requests. "auth" redirects to identity provider, "deny" results in a 401 response, "pass" will allow the request without authentication.                                                 |
| proxy_opts                           | object   | False    |                       |                                  | HTTP proxy that the OpenID provider is behind.                                                                                                                                                                                  |
| proxy_opts.http_proxy     | string   | False    |                       | http://proxy-server:port         | HTTP proxy server address.                                                                                                                                                                                                            |
| proxy_opts.https_proxy    | string   | False    |                       | http://proxy-server:port         | HTTPS proxy server address.                                                                                                                                                                                                           |
| proxy_opts.http_proxy_authorization  | string   | False    |                       | Basic [base64 username:password] | Default `Proxy-Authorization` header value to be used with `http_proxy`. Can be overridden with custom `Proxy-Authorization` request header.                                                                                                                                                              |
| proxy_opts.https_proxy_authorization | string   | False    |                       | Basic [base64 username:password] | Default `Proxy-Authorization` header value to be used with `https_proxy`. Cannot be overridden with custom `Proxy-Authorization` request header since with with HTTPS the authorization is completed when connecting.                         |
| proxy_opts.no_proxy                  | string   | False    |                       |                                  | Comma separated list of hosts that should not be proxied.                                                                                                                                                                             |
| authorization_params                 | object   | False    |                       |                                  | Additional parameters to send in the request to the authorization endpoint.                                                                                                                                                    |
| client_rsa_private_key | string | False |  |  | Client RSA private key used to sign JWT. |
| client_rsa_private_key_id | string | False |  |  | Client RSA private key ID used to compute a signed JWT. |
| client_jwt_assertion_expires_in | integer | False | 60 |  | Life duration of the signed JWT in seconds. |
| renew_access_token_on_expiry | boolean | False | true |  | If true, attempt to silently renew the access token when it expires or if a refresh token is available. If the token fails to renew, redirect user for re-authentication. |
| access_token_expires_in | integer | False |  |  | Lifetime of the access token in seconds if no `expires_in` attribute is present in the token endpoint response. |
| refresh_session_interval | integer | False |  |  | Time interval to refresh user ID token without requiring re-authentication. When not set, it will not check the expiration time of the session issued to the client by the gateway. If set to 900, it means refreshing the user's id_token (or session in the browser) after 900 seconds without requiring re-authentication. |
| iat_slack | integer | False | 120 |  | Tolerance of clock skew in seconds with the `iat` claim in an ID token. |
| accept_none_alg | boolean | False | false |  | Set to true if the OpenID provider does not sign its ID token, such as when the signature algorithm is set to `none`. |
| accept_unsupported_alg | boolean | False | true |  | If true, ignore ID token signature to accept unsupported signature algorithm. |
| access_token_expires_leeway | integer | False | 0 |  | Expiration leeway in seconds for access token renewal. When set to a value greater than 0, token renewal will take place the set amount of time before token expiration. This avoids errors in case the access token just expires when arriving to the resource server. |
| force_reauthorize | boolean | False | false |  | If true, execute the authorization flow even when a token has been cached. |
| use_nonce | boolean | False | false |  | If true, enable nonce parameter in authorization request. |
| revoke_tokens_on_logout | boolean | False | false |  | If true, notify the authorization server a previously obtained refresh or access token is no longer needed at the revocation endpoint. |
| jwk_expires_in | integer | False | 86400 |  | Expiration time for JWK cache in seconds. |
| jwt_verification_cache_ignore | boolean | False | false |  | If true, force re-verification for a bearer token and ignore any existing cached verification results. |
| cache_segment | string | False |  |  | Optional name of a cache segment, used to separate and differentiate caches used by token introspection or JWT verification. |
| introspection_interval | integer | False | 0 |  | TTL of the cached and introspected access token in seconds. |
| introspection_expiry_claim | string | False |  |  | Name of the expiry claim, which controls the TTL of the cached and introspected access token. The default value is 0, which means this option is not used and the plugin defaults to use the TTL passed by expiry claim defined in `introspection_expiry_claim`. If `introspection_interval` is larger than 0 and less than the TTL passed by expiry claim defined in `introspection_expiry_claim`, use `introspection_interval`. |
| introspection_addon_headers | string[] | False |  |  | Array of strings. Used to append additional header values to the introspection HTTP request. If the specified header does not exist in origin request, value will not be appended. |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Scenarios

:::tip

Tutorial: [Use Keycloak with API Gateway to secure APIs](https://apisix.apache.org/blog/2022/07/06/use-keycloak-with-api-gateway-to-secure-apis/)

:::

This plugin offers two scenarios:

1. Authentication between Services: Set `bearer_only` to `true` and configure the `introspection_endpoint` or `public_key` attribute. In this scenario, APISIX will reject requests without a token or invalid token in the request header.

2. Authentication between Browser and Identity Providers: Set `bearer_only` to `false.` After successful authentication, this plugin can obtain and manage the token in the cookie, and subsequent requests will use the token. In this mode, the user session will be stored in the browser as a cookie and this data is encrypted, so you have to set a key for encryption via `session.secret`.

### Token introspection

[Token introspection](https://www.oauth.com/oauth2-servers/token-introspection-endpoint/) validates a request by verifying the token with an OAuth 2.0 authorization server.

You should first create a trusted client in the identity server and generate a valid JWT token for introspection.

The image below shows an example token introspection flow via a Gateway:

![token introspection](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/oauth-1.png)

The example below shows how you can enable the Plugin on Route. The Route below will protect the Upstream by introspecting the token provided in the request header:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
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

This section covers a few commonly seen issues when working with this plugin to help you troubleshoot.

### APISIX Cannot Connect to OpenID provider

If APISIX fails to resolve or cannot connect to the OpenID provider, double check the DNS settings in your configuration file `config.yaml` and modify as needed.

### No Session State Found

If you encounter a `500 internal server error` with the following message in the log when working with [authorization code flow](#authorization-code-flow), there could be a number of reasons.

```text
the error request to the redirect_uri path, but there's no session state found
```

#### 1. Misconfigured Redirection URI

A common misconfiguration is to configure the `redirect_uri` the same as the URI of the route. When a user initiates a request to visit the protected resource, the request directly hits the redirection URI with no session cookie in the request, which leads to the no session state found error.

To properly configure the redirection URI, make sure that the `redirect_uri` matches the route where the plugin is configured, without being fully identical. For instance, a correct configuration would be to configure `uri` of the route to `/api/v1/*` and the path portion of the `redirect_uri` to `/api/v1/redirect`.

You should also ensure that the `redirect_uri` include the scheme, such as `http` or `https`.

#### 2. Missing Session Secret

If you deploy APISIX in the [standalone mode](../deployment-modes.md#standalone), make sure that `session.secret` is configured.

User sessions are stored in browser as cookies and encrypted with session secret. The secret is automatically generated and saved to etcd if no secret is configured through the `session.secret` attribute. However, in standalone mode, etcd is no longer the configuration center. Therefore, you should explicitly configure `session.secret` for this plugin in the YAML configuration center `apisix.yaml`.

#### 3. Cookie Not Sent or Absent

Check if the [`SameSite`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#samesitesamesite-value) cookie attribute is properly set (i.e. if your application needs to send the cookie cross sites) to see if this could be a factor that prevents the cookie being saved to the browser's cookie jar or being sent from the browser.

#### 4. Upstream Sent Too Big Header

If you have NGINX sitting in front of APISIX to proxy client traffic, see if you observe the following error in NGINX's `error.log`:

```text
upstream sent too big header while reading response header from upstream
```

If so, try adjusting `proxy_buffers`, `proxy_buffer_size`, and `proxy_busy_buffers_size` to larger values.

#### 5. Invalid Client Secret

Verify if `client_secret` is valid and correct. An invalid `client_secret` would lead to an authentication failure and no token shall be returned and stored in session.
