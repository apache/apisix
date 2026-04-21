---
title: authz-keycloak
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: The authz-keycloak Plugin integrates with Keycloak for user authentication and authorization, enhancing API security and management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/authz-keycloak" />
</head>

## Description

The `authz-keycloak` Plugin can be used to add authentication with [Keycloak Identity Server](https://www.keycloak.org/).

:::tip

Although this Plugin was developed to work with Keycloak, it should work with any OAuth/OIDC and UMA compliant identity providers as well.

:::

Refer to [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/) for more information on Keycloak.

## Attributes

| Name                                         | Type          | Required | Default                                       | Valid values                                                           | Description                                                                                                                                                                                                                                           |
|----------------------------------------------|---------------|----------|-----------------------------------------------|------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| discovery                                    | string        | False    |                                               | https://host.domain/realms/foo/.well-known/uma2-configuration      | URL to [discovery document](https://www.keycloak.org/docs/latest/authorization_services/index.html) of Keycloak Authorization Services.                                                                                                               |
| token_endpoint                               | string        | False    |                                               | https://host.domain/realms/foo/protocol/openid-connect/token       | An OAuth2-compliant token endpoint that supports the `urn:ietf:params:oauth:grant-type:uma-ticket` grant type. If provided, overrides the value from discovery.                                                                                       |
| resource_registration_endpoint               | string        | False    |                                               | https://host.domain/realms/foo/authz/protection/resource_set       | A UMA-compliant resource registration endpoint. If provided, overrides the value from discovery.                                                                                                                                                      |
| client_id                                    | string        | True     |                                               |                                                                        | The identifier of the resource server to which the client is seeking access.                                                                                                                                                                         |
| client_secret                                | string        | False    |                                               |                                                                        | The client secret, if required. You can use APISIX secret to store and reference this value. APISIX currently supports storing secrets in two ways: [Environment Variables and HashiCorp Vault](../terminology/secret.md).                            |
| grant_type                                   | string        | False    | "urn:ietf:params:oauth:grant-type:uma-ticket" | ["urn:ietf:params:oauth:grant-type:uma-ticket"]                        |                                                                                                                                                                                                                                                       |
| policy_enforcement_mode                      | string        | False    | "ENFORCING"                                   | ["ENFORCING", "PERMISSIVE"]                                            |                                                                                                                                                                                                                                                       |
| permissions                                  | array[string] | False    |                                               |                                                                        | An array of strings, each representing a set of one or more resources and scopes the client is seeking access.                                                                                                                                        |
| lazy_load_paths                              | boolean       | False    | false                                         |                                                                        | When set to true, dynamically resolves the request URI to resource(s) using the resource registration endpoint instead of the static permission.                                                                                                      |
| http_method_as_scope                         | boolean       | False    | false                                         |                                                                        | When set to true, maps the HTTP request type to scope of the same name and adds to all requested permissions.                                                                                                                                         |
| timeout                                      | integer       | False    | 3000                                          | [1000, ...]                                                            | Timeout in ms for the HTTP connection with the Identity Server.                                                                                                                                                                                       |
| access_token_expires_in                      | integer       | False    | 300                                           | [1, ...]                                                               | Expiration time(s) of the access token.                                                                                                                                                                                                               |
| access_token_expires_leeway                  | integer       | False    | 0                                             | [0, ...]                                                               | Expiration leeway(s) for access_token renewal. When set, the token will be renewed access_token_expires_leeway seconds before expiration. This avoids errors in cases where the access_token just expires when reaching the OAuth Resource Server.    |
| refresh_token_expires_in                     | integer       | False    | 3600                                          | [1, ...]                                                               | The expiration time(s) of the refresh token.                                                                                                                                                                                                          |
| refresh_token_expires_leeway                 | integer       | False    | 0                                             | [0, ...]                                                               | Expiration leeway(s) for refresh_token renewal. When set, the token will be renewed refresh_token_expires_leeway seconds before expiration. This avoids errors in cases where the refresh_token just expires when reaching the OAuth Resource Server. |
| ssl_verify                                   | boolean       | False    | true                                          |                                                                        | When set to true, verifies if TLS certificate matches hostname.                                                                                                                                                                                       |
| cache_ttl_seconds                            | integer       | False    | 86400 (equivalent to 24h)                     | positive integer >= 1                                                  | Maximum time in seconds up to which the Plugin caches discovery documents and tokens used by the Plugin to authenticate to Keycloak.                                                                                                                  |
| keepalive                                    | boolean       | False    | true                                          |                                                                        | When set to true, enables HTTP keep-alive to keep connections open after use. Set to `true` if you are expecting a lot of requests to Keycloak.                                                                                                       |
| keepalive_timeout                            | integer       | False    | 60000                                         | positive integer >= 1000                                               | Idle time after which the established HTTP connections will be closed.                                                                                                                                                                                |
| keepalive_pool                               | integer       | False    | 5                                             | positive integer >= 1                                                  | Maximum number of connections in the connection pool.                                                                                                                                                                                                 |
| access_denied_redirect_uri                   | string        | False    |                                               | [1, 2048]                                                              | URI to redirect the user to instead of returning an error message like `"error_description":"not_authorized"`.                                                                                                                                        |
| password_grant_token_generation_incoming_uri | string        | False    |                                               | /api/token                                                             | Set this to generate token using the password grant type. The Plugin will compare incoming request URI to this value.                                                                                                                                 |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

### Discovery and Endpoints

It is recommended to use the `discovery` attribute as the `authz-keycloak` Plugin can discover the Keycloak API endpoints from it.

If set, the `token_endpoint` and `resource_registration_endpoint` will override the values obtained from the discovery document.

### Client ID and Secret

The Plugin needs the `client_id` attribute for identification and to specify the context in which to evaluate permissions when interacting with Keycloak.

If the `lazy_load_paths` attribute is set to true, then the Plugin additionally needs to obtain an access token for itself from Keycloak. In such cases, if the client access to Keycloak is confidential, you need to configure the `client_secret` attribute.

### Policy Enforcement Mode

The `policy_enforcement_mode` attribute specifies how policies are enforced when processing authorization requests sent to the server.

#### `ENFORCING` Mode

Requests are denied by default even when there is no policy associated with a resource.

The `policy_enforcement_mode` is set to `ENFORCING` by default.

#### `PERMISSIVE` Mode

Requests are allowed when there is no policy associated with a given resource.

### Permissions

When handling incoming requests, the Plugin can determine the permissions to check with Keycloak statically or dynamically from the properties of the request.

If the `lazy_load_paths` attribute is set to `false`, the permissions are taken from the `permissions` attribute. Each entry in `permissions` needs to be formatted as expected by the token endpoint's `permission` parameter. See [Obtaining Permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions).

:::note

A valid permission can be a single resource or a resource paired with one or more scopes.

:::

If the `lazy_load_paths` attribute is set to `true`, the request URI is resolved to one or more resources configured in Keycloak using the resource registration endpoint. The resolved resources are used as the permissions to check.

:::note

This requires the Plugin to obtain a separate access token for itself from the token endpoint. So, make sure to set the `Service Accounts Enabled` option in the client settings in Keycloak.

Also make sure that the issued access token contains the `resource_access` claim with the `uma_protection` role to ensure that the Plugin is able to query resources through the Protection API.

:::

### Automatically Mapping HTTP Method to Scope

The `http_method_as_scope` is often used together with `lazy_load_paths` but can also be used with a static permission list.

If the `http_method_as_scope` attribute is set to `true`, the Plugin maps the request's HTTP method to the scope with the same name. The scope is then added to every permission to check.

If the `lazy_load_paths` attribute is set to false, the Plugin adds the mapped scope to any of the static permissions configured in the `permissions` attribute—even if they contain one or more scopes already.

### Generating a Token Using `password` Grant

To generate a token using `password` grant, you can set the value of the `password_grant_token_generation_incoming_uri` attribute.

If the incoming URI matches the configured attribute and the request method is POST, a token is generated using the `token_endpoint`.

You also need to add `application/x-www-form-urlencoded` as `Content-Type` header and `username` and `password` as parameters.

## Examples

The examples below demonstrate how you can configure `authz-keycloak` for different scenarios.

To follow along, complete the [preliminary setups](#set-up-keycloak) for Keycloak.

:::note
You can fetch the `admin_key` from `conf/config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Set Up Keycloak

#### Start Keycloak

Start a Keycloak instance named `apisix-quickstart-keycloak` with the administrator name `quickstart-admin` and password `quickstart-admin-pass` in [development mode](https://www.keycloak.org/server/configuration#_starting_keycloak_in_development_mode) in Docker:

```shell
docker run -d --name "apisix-quickstart-keycloak" \
  -e 'KEYCLOAK_ADMIN=quickstart-admin' \
  -e 'KEYCLOAK_ADMIN_PASSWORD=quickstart-admin-pass' \
  -p 8080:8080 \
  quay.io/keycloak/keycloak:18.0.2 start-dev
```

Save the Keycloak IP to an environment variable to be referenced in future configuration:

```shell
KEYCLOAK_IP=192.168.42.145    # replace with your host IP
```

Navigate to `http://localhost:8080` in browser and click **Administration Console**:

![admin-console](https://static.api7.ai/uploads/2024/01/12/yEKlaSf5_admin-console.png)

Enter the administrator's username `quickstart-admin` and password `quickstart-admin-pass` to sign in:

![admin-signin](https://static.api7.ai/uploads/2024/01/12/GYIVrPyb_signin.png)

#### Create a Realm

In the left menu, hover over **Master**, and select **Add realm** in the dropdown:

![create-realm](https://static.api7.ai/uploads/2024/01/12/563XIJPK_add-realm.png)

Enter the realm name `quickstart-realm` and click **Create** to create it:

![add-realm](https://static.api7.ai/uploads/2024/01/12/0lD21Z8R_create-realm.png)

#### Create a Client

Click **Clients** > **Create** to open the **Add Client** page:

![create-client](https://static.api7.ai/uploads/2024/01/12/nHxgXyd9_create-client.png)

Enter **Client ID** as `apisix-quickstart-client`, keep the **Client Protocol** as `openid-connect` and **Save**:

![add-client](https://static.api7.ai/uploads/2024/01/12/7YSCHCnp_add-client.png)

The client `apisix-quickstart-client` is created. After redirecting to the detailed page, select `confidential` as the **Access Type**:

![client-access-type-confidential](https://static.api7.ai/uploads/2024/01/12/L7cahPUe_confidential.png)

When the user login is successful during the SSO, Keycloak will carry the state and code to redirect the client to the addresses in **Valid Redirect URIs**. For simplicity of demonstration, enter wildcard `*` to accept any redirect URI:

![client-redirect](https://static.api7.ai/uploads/2024/01/12/B3VGbQbW_redirect-uri.png)

Enable authorization for the client, which should also enable service accounts with an assigned role `uma_protection` automatically:

![enable-authorization](https://static.api7.ai/uploads/2024/01/05/S4we4KO9_enable-auth.png)

Select **Save** to apply custom configurations.

#### Save Client ID and Secret

Click on **Clients** > `apisix-quickstart-client` > **Credentials**, and copy the client secret from **Secret**:

![client-secret](https://static.api7.ai/uploads/2024/01/12/3VqiXdf9_client-secret.png)

Save the OIDC client ID and secret to environment variables:

```shell
OIDC_CLIENT_ID=apisix-quickstart-client
OIDC_CLIENT_SECRET=bSaIN3MV1YynmtXvU8lKkfeY0iwpr9cH  # replace with your value
```

#### Request Access Token

Request an access token from Keycloak:

```shell
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=client_credentials' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET''
```

You should see a response similar to the following:

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0...","expires_in":300,"refresh_expires_in":0,"token_type":"Bearer","not-before-policy":0,"scope":"email profile"}
```

Save the token to an environment variable:

```shell
# replace with your access token
ACCESS_TOKEN=<your_access_token>
```

### Use Lazy Load Path and Resource Registration Endpoint

The examples below demonstrate how you can configure the plugin to dynamically resolve the request URI to resource(s) using the resource registration endpoint instead of the static permissions.

Create a route with `authz-keycloak-route` as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/anything",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": true,
        "resource_registration_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/authz/protection/resource_set",
        "discovery": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/.well-known/uma2-configuration",
        "client_id": "'"$OIDC_CLIENT_ID"'",
        "client_secret": "'"$OIDC_CLIENT_SECRET"'"
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

- Set `lazy_load_paths` to `true`.
- Set `resource_registration_endpoint` to Keycloak's UMA-compliant resource registration endpoint. Required when `lazy_load_paths` is `true` and `discovery` is not provided.
- Set `discovery` to the discovery document endpoint of Keycloak authorization services.
- Set `client_id` to client ID created previously.
- Set `client_secret` to client secret created previously. Required when `lazy_load_paths` is `true`.

Send a request to the route:

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Bearer eyJhbGciOiJSU...",
    ...
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 108.180.51.111",
  "url": "http://127.0.0.1/anything"
}
```

### Use Static Permissions

The examples below demonstrate how you can configure Keycloak for scope-based permission associated with a client scope policy, and configure the `authz-keycloak` plugin to use static permissions.

#### Create Scope in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Authorization Scopes**, and click **Create** to open the **Add Scope** page:

![add-scope](https://static.api7.ai/uploads/2024/01/06/bVHhiALe_auth-scope.png)

Enter the scope names as `access` and click **Save**:

![create-new-scope](https://static.api7.ai/uploads/2024/01/06/xPorYwK3_save-scope.png)

#### Create Resource in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Resources** and click **Create** to open the **Add Resource** page:

![create-resource](https://static.api7.ai/uploads/2024/01/06/15DJ9HAU_create-resource.png)

Enter the resource names `httpbin-anything`, URI `/anything`, scope `access`, and click **Save**:

![save-resource](https://static.api7.ai/uploads/2024/01/06/epuAPgos_save-resource.png)

#### Create Client Scope in Keycloak

Go to **Client Scopes** and click **Create** to open the **Add client scope** page:

![create-client-scope](https://static.api7.ai/uploads/2024/01/11/PyseoG7T_creat-client-scope.png)

Enter the scope name `httpbin-access` and click **Save**:

![save-client-scope](https://static.api7.ai/uploads/2024/01/12/5xQl0Xbx_save-client-scope.png)

#### Create Policy in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Policies** > **Create Policies** and select **Client Scope** from the dropdown to open the **Add Client Scope Policy** page:

![create-policy](https://static.api7.ai/uploads/2024/01/06/7UtT3cF6_create-policy.png)

Enter the policy name `access-client-scope-policy` for client scope `httpbin-access`, check the **Required** box, and click **Save**:

![save-policy](https://static.api7.ai/uploads/2024/12/12/2DR0K39f_add_client_scope.png)

#### Create Permission in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Permissions** > **Create Permissions** and select **Scope-Based** from the dropdown to open the **Add Scope Permission** page:

![create-permission](https://static.api7.ai/uploads/2024/12/12/0PWsJUti_create_permission.png)

Enter the permission name `access-scope-perm`, select the `access` scope, apply the policy `access-client-scope-policy`, and click **Save**:

![add-scope-permission](https://static.api7.ai/uploads/2024/01/12/Y0vlk1Tj_add-scope-permission.png)

#### Assign Client Scope

Go to **Clients** > **`apisix-quickstart-client`** > **Client Scopes** and add `httpbin-access` to the default client scopes:

![add-client-scope](https://static.api7.ai/uploads/2024/01/06/sJKUMUcP_add-client-scope.png)

#### Configure APISIX

Create a route with `authz-keycloak-route` as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/anything",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": false,
        "discovery": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/.well-known/uma2-configuration",
        "permissions": ["httpbin-anything#access"],
        "client_id": "apisix-quickstart-client"
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

- Set `lazy_load_paths` to `false`.
- Set `discovery` to the discovery document endpoint of Keycloak authorization services.
- Set `permissions` to resource `httpbin-anything` and scope `access`.

Send a request to the route:

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Bearer eyJhbGciOiJSU...",
    ...
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 108.180.51.111",
  "url": "http://127.0.0.1/anything"
}
```

If you remove the client scope `httpbin-access` for `apisix-quickstart-client`, you should receive a `401 Unauthorized` response when requesting the resource.

### Generate Token with Password Grant at Custom Token Endpoint

The examples below demonstrate how you can generate a token using the password grant at a custom endpoint.

#### Create User in Keycloak

To use the password grant, you should first create a user.

Go to **Users** > **Add user** and click on **Add user**:

![add-user](https://static.api7.ai/uploads/2024/01/12/IBCav8aa_add-user.png)

Enter the **Username** as `quickstart-user` and select **Save**:

![save-user](https://static.api7.ai/uploads/2024/01/12/3fUQOFWg_save-user.png)

Click on **Credentials**, then set the **Password** as `quickstart-user-pass`. Switch **Temporary** to `OFF` so that you do not need to change the password the first time you log in:

![set-password](https://static.api7.ai/uploads/2024/01/12/aoabcBbC_set-password.png)

#### Configure APISIX

Create a route with `authz-keycloak-route` as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/api/*",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": true,
        "resource_registration_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/authz/protection/resource_set",
        "client_id": "'"$OIDC_CLIENT_ID"'",
        "client_secret": "'"$OIDC_CLIENT_SECRET"'",
        "token_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/protocol/openid-connect/token",
        "password_grant_token_generation_incoming_uri": "/api/token"
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

- Set `token_endpoint` to the Keycloak token endpoint. Required when discovery document is not provided.
- Set `password_grant_token_generation_incoming_uri` to a custom URI path users can obtain tokens from.

Send a request to the configured token endpoint. Note that the request should use the POST method and `application/x-www-form-urlencoded` as the `Content-Type`:

```shell
OIDC_USER=quickstart-user
OIDC_PASSWORD=quickstart-user-pass

curl "http://127.0.0.1:9080/api/token" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d 'username='$OIDC_USER'' \
  -d 'password='$OIDC_PASSWORD''
```

You should see a JSON response with the access token, similar to the following:

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ6U3FFaXN6VlpuYi1sRWMzZkp0UHNpU1ZZcGs4RGN3dXI1Mkx5V05aQTR3In0...","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0YjFiNTQ3Yi0zZmZjLTQ5YzQtYjE2Ni03YjdhNzIxMjk1ODcifQ...","token_type":"Bearer","not-before-policy":0,"session_state":"b16b262e-1056-4515-a455-f25e077ccb76","scope":"profile email"}
```
