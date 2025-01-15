---
title: authz-keycloak
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: This document contains information about the Apache APISIX authz-keycloak Plugin.
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

The `authz-keycloak` Plugin can be used to add authentication with [Keycloak Identity Server](https://www.keycloak.org/).

:::tip

Although this Plugin was developed to work with Keycloak, it should work with any OAuth/OIDC and UMA compliant identity providers as well.

:::

Refer to [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/) for more information on Keycloak.

## Attributes

| Name                                         | Type          | Required | Default                                       | Valid values                                                       | Description                                                                                                                                                                                                                                           |
|----------------------------------------------|---------------|----------|-----------------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| discovery                                    | string        | False    |                                               | https://host.domain/realms/foo/.well-known/uma2-configuration | URL to [discovery document](https://www.keycloak.org/docs/latest/authorization_services/index.html) of Keycloak Authorization Services.                                                                                                |
| token_endpoint                               | string        | False    |                                               | https://host.domain/realms/foo/protocol/openid-connect/token  | An OAuth2-compliant token endpoint that supports the `urn:ietf:params:oauth:grant-type:uma-ticket` grant type. If provided, overrides the value from discovery.                                                                                       |
| resource_registration_endpoint               | string        | False    |                                               | https://host.domain/realms/foo/authz/protection/resource_set  | A UMA-compliant resource registration endpoint. If provided, overrides the value from discovery.                                                                                                                                                      |
| client_id                                    | string        | True     |                                               |                                                                    | The identifier of the resource server to which the client is seeking access.                                                                                                                                                                         |
| client_secret                                | string        | False    |                                               |                                                                    | The client secret, if required. You can use APISIX secret to store and reference this value. APISIX currently supports storing secrets in two ways. [Environment Variables and HashiCorp Vault](../terminology/secret.md)                                                                                                                                                                                                                         |
| grant_type                                   | string        | False    | "urn:ietf:params:oauth:grant-type:uma-ticket" | ["urn:ietf:params:oauth:grant-type:uma-ticket"]                    |                                                                                                                                                                                                                                                       |
| policy_enforcement_mode                      | string        | False    | "ENFORCING"                                   | ["ENFORCING", "PERMISSIVE"]                                        |                                                                                                                                                                                                                                                       |
| permissions                                  | array[string] | False    |                                               |                                                                    | An array of strings, each representing a set of one or more resources and scopes the client is seeking access.                                                                                                                                        |
| lazy_load_paths                              | boolean       | False    | false                                         |                                                                    | When set to true, dynamically resolves the request URI to resource(s) using the resource registration endpoint instead of the static permission.                                                                                                      |
| http_method_as_scope                         | boolean       | False    | false                                         |                                                                    | When set to true, maps the HTTP request type to scope of the same name and adds to all requested permissions.                                                                                                                                         |
| timeout                                      | integer       | False    | 3000                                          | [1000, ...]                                                        | Timeout in ms for the HTTP connection with the Identity Server.                                                                                                                                                                                       |
| access_token_expires_in                      | integer       | False    | 300                                           | [1, ...]                                                           | Expiration time(s) of the access token.                                                                                                                                                                                                               |
| access_token_expires_leeway                  | integer       | False    | 0                                             | [0, ...]                                                           | Expiration leeway(s) for access_token renewal. When set, the token will be renewed access_token_expires_leeway seconds before expiration. This avoids errors in cases where the access_token just expires when reaching the OAuth Resource Server.    |
| refresh_token_expires_in                     | integer       | False    | 3600                                          | [1, ...]                                                           | The expiration time(s) of the refresh token.                                                                                                                                                                                                          |
| refresh_token_expires_leeway                 | integer       | False    | 0                                             | [0, ...]                                                           | Expiration leeway(s) for refresh_token renewal. When set, the token will be renewed refresh_token_expires_leeway seconds before expiration. This avoids errors in cases where the refresh_token just expires when reaching the OAuth Resource Server. |
| ssl_verify                                   | boolean       | False    | true                                          |                                                                    | When set to true, verifies if TLS certificate matches hostname.                                                                                                                                                                                       |
| cache_ttl_seconds                            | integer       | False    | 86400 (equivalent to 24h)                     | positive integer >= 1                                              | Maximum time in seconds up to which the Plugin caches discovery documents and tokens used by the Plugin to authenticate to Keycloak.                                                                                                                  |
| keepalive                                    | boolean       | False    | true                                          |                                                                    | When set to true, enables HTTP keep-alive to keep connections open after use. Set to `true` if you are expecting a lot of requests to Keycloak.                                                                                                       |
| keepalive_timeout                            | integer       | False    | 60000                                         | positive integer >= 1000                                           | Idle time after which the established HTTP connections will be closed.                                                                                                                                                                                |
| keepalive_pool                               | integer       | False    | 5                                             | positive integer >= 1                                              | Maximum number of connections in the connection pool.                                                                                                                                                                                                 |
| access_denied_redirect_uri                   | string        | False    |                                               | [1, 2048]                                                          | URI to redirect the user to instead of returning an error message like `"error_description":"not_authorized"`.                                                                                                                                        |
| password_grant_token_generation_incoming_uri | string        | False    |                                               | /api/token                                                         | Set this to generate token using the password grant type. The Plugin will compare incoming request URI to this value.                                                                                                                                 |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

### Discovery and endpoints

It is recommended to use the `discovery` attribute as the `authz-keycloak` Plugin can discover the Keycloak API endpoints from it.

If set, the `token_endpoint` and `resource_registration_endpoint` will override the values obtained from the discovery document.

### Client ID and secret

The Plugin needs the `client_id` attribute for identification and to specify the context in which to evaluate permissions when interacting with Keycloak.

If the `lazy_load_paths` attribute is set to true, then the Plugin additionally needs to obtain an access token for itself from Keycloak. In such cases, if the client access to Keycloak is confidential, you need to configure the `client_secret` attribute.

### Policy enforcement mode

The `policy_enforcement_mode` attribute specifies how policies are enforced when processing authorization requests sent to the server.

#### `ENFORCING` mode

Requests are denied by default even when there is no policy associated with a resource.

The `policy_enforcement_mode` is set to `ENFORCING` by default.

#### `PERMISSIVE` mode

Requests are allowed when there is no policy associated with a given resource.

### Permissions

When handling incoming requests, the Plugin can determine the permissions to check with Keycloak statically or dynamically from the properties of the request.

If the `lazy_load_paths` attribute is set to `false`, the permissions are taken from the `permissions` attribute. Each entry in `permissions` needs to be formatted as expected by the token endpoint's `permission` parameter. See [Obtaining Permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions).

:::note

A valid permission can be a single resource or a resource paired with on or more scopes.

:::

If the `lazy_load_paths` attribute is set to `true`, the request URI is resolved to one or more resources configured in Keycloak using the resource registration endpoint. The resolved resources are used as the permissions to check.

:::note

This requires the Plugin to obtain a separate access token for itself from the token endpoint. So, make sure to set the `Service Accounts Enabled` option in the client settings in Keycloak.

Also make sure that the issued access token contains the `resource_access` claim with the `uma_protection` role to ensure that the Plugin is able to query resources through the Protection API.

:::

### Automatically mapping HTTP method to scope

The `http_method_as_scope` is often used together with `lazy_load_paths` but can also be used with a static permission list.

If the `http_method_as_scope` attribute is set to `true`, the Plugin maps the request's HTTP method to the scope with the same name. The scope is then added to every permission to check.

If the `lazy_load_paths` attribute is set to false, the Plugin adds the mapped scope to any of the static permissions configured in the `permissions` attribute—even if they contain on or more scopes already.

### Generating a token using `password` grant

To generate a token using `password` grant, you can set the value of the `password_grant_token_generation_incoming_uri` attribute.

If the incoming URI matches the configured attribute and the request method is POST, a token is generated using the `token_endpoint`.

You also need to add `application/x-www-form-urlencoded` as `Content-Type` header and `username` and `password` as parameters.

The example below shows a request if the `password_grant_token_generation_incoming_uri` is `/api/token`:

```shell
curl --location --request POST 'http://127.0.0.1:9080/api/token' \
--header 'Accept: application/json, text/plain, */*' \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode 'username=<User_Name>' \
--data-urlencode 'password=<Password>'
```

## Enable Plugin

The example below shows how you can enable the `authz-keycloak` Plugin on a specific Route. `${realm}` represents the realm name in Keycloak.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/get",
    "plugins": {
        "authz-keycloak": {
            "token_endpoint": "http://127.0.0.1:8090/realms/${realm}/protocol/openid-connect/token",
            "permissions": ["resource name#scope name"],
            "client_id": "Client ID"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Example usage

Once you have enabled the Plugin on a Route you can use it.

First, you have to get the JWT token from Keycloak:

```shell
curl "http://<YOUR_KEYCLOAK_HOST>/realms/<YOUR_REALM>/protocol/openid-connect/token" \
  -d "client_id=<YOUR_CLIENT_ID>" \
  -d "client_secret=<YOUR_CLIENT_SECRET>" \
  -d "username=<YOUR_USERNAME>" \
  -d "password=<YOUR_PASSWORD>" \
  -d "grant_type=password"
```

You should see a response similar to the following:

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0.eyJleHAiOjE3MDMyOTAyNjAsImlhdCI6MTcwMzI4OTk2MCwianRpIjoiMjJhOGFmMzItNDM5Mi00Yzg3LThkM2UtZDkyNDVmZmNiYTNmIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjAyZWZlY2VlLTBmYTgtNDg1OS1iYmIwLTgyMGZmZDdjMWRmYSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInNlc3Npb25fc3RhdGUiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJhY3IiOiIxIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtcXVpY2tzdGFydC1yZWFsbSIsIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJzaWQiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsInByZWZlcnJlZF91c2VybmFtZSI6InF1aWNrc3RhcnQtdXNlciJ9.WNZQiLRleqCxw-JS-MHkqXnX_BPA9i6fyVHqF8l-L-2QxcqTAwbIp7AYKX-z90CG6EdRXOizAEkQytB32eVWXaRkLeTYCI7wIrT8XSVTJle4F88ohuBOjDfRR61yFh5k8FXXdAyRzcR7tIeE2YUFkRqw1gCT_VEsUuXPqm2wTKOmZ8fRBf4T-rP4-ZJwPkHAWc_nG21TmLOBCSulzYqoC6Lc-OvX5AHde9cfRuXx-r2HhSYs4cXtvX-ijA715MY634CQdedheoGca5yzPsJWrAlBbCruN2rdb4u5bDxKU62pJoJpmAsR7d5qYpYVA6AsANDxHLk2-W5F7I_IxqR0YQ","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJjN2IwYmY4NC1kYjk0LTQ5YzctYWIyZC01NmU3ZDc1MmRkNDkifQ.eyJleHAiOjE3MDMyOTE3NjAsImlhdCI6MTcwMzI4OTk2MCwianRpIjoiYzcyZjAzMzctYmZhNS00MWEzLTlhYjEtZmJlNGY0NmZjMDgxIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwic3ViIjoiMDJlZmVjZWUtMGZhOC00ODU5LWJiYjAtODIwZmZkN2MxZGZhIiwidHlwIjoiUmVmcmVzaCIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInNlc3Npb25fc3RhdGUiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJzaWQiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYifQ.7AH7ppbVOlkYc9CoJ7kLSlDUkmFuNga28Amugn2t724","token_type":"Bearer","not-before-policy":0,"session_state":"5c23f5dd-a7fa-4e2b-9d14-62b5c626e546","scope":"email profile"}
```

Now you can make requests with the access token:

```shell
curl http://127.0.0.1:9080/get -H 'Authorization: Bearer ${ACCESS_TOKEN}'
```

To learn more about how you can integrate authorization policies into your API workflows you can checkout the unit test [authz-keycloak.t](https://github.com/apache/apisix/blob/master/t/plugin/authz-keycloak.t).

Run the following Docker image and go to `http://localhost:8090` to view the associated policies for the unit tests.

```bash
docker run -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=123456 -p 8090:8080 sshniro/keycloak-apisix
```

The image below shows how the policies are configured in the Keycloak server:

![Keycloak policy design](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/authz-keycloak.png)

## Delete Plugin

To remove the `authz-keycloak` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Plugin roadmap

- Currently, the `authz-keycloak` Plugin requires you to define the resource name and the required scopes to enforce policies for a Route. Keycloak's official adapted (Java, Javascript) provides path matching by querying Keycloak paths dynamically and lazy loading the paths to identity resources. Upcoming releases of the Plugin will support this function.

- To support reading scope and configurations from the Keycloak JSON file.
