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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `authz-keycloak` Plugin supports the integration with [Keycloak](https://www.keycloak.org/) to authenticate and authorize users. See Keycloak's [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/) for more information about the configuration options available in this Plugin.

While the Plugin was developed for Keycloak, it could theoretically be used with other OAuth/OIDC and UMA-compliant identity providers.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| client_id | string | True | | | Client ID. |
| client_secret | string | False | | | Client secret. The value is encrypted with AES before being stored in etcd. |
| discovery | string | False | | | URL to the discovery document. |
| token_endpoint | string | False | | | Token endpoint that supports the `urn:ietf:params:oauth:grant-type:uma-ticket` grant type to obtain access token. If provided, overrides the value from the discovery document. |
| resource_registration_endpoint | string | False | | | A UMA-compliant resource registration endpoint. Required when `lazy_load_paths` is `true`. The Plugin will first look for the resource registration endpoint from this configuration option; if not found, look for the resource registration endpoint from the discovery document. |
| grant_type | string | False | `urn:ietf:params:oauth:grant-type:uma-ticket` | `urn:ietf:params:oauth:grant-type:uma-ticket` | Must be set to `urn:ietf:params:oauth:grant-type:uma-ticket`. |
| policy_enforcement_mode | string | False | `ENFORCING` | `ENFORCING` or `PERMISSIVE` | The mode of [policy enforcement](https://www.keycloak.org/docs/latest/authorization_services/index.html#policy-enforcement). In `ENFORCING` mode, requests are denied when there is no policy associated with a given resource. In `PERMISSIVE` mode, requests are allowed when there is no policy associated with a given resource. |
| permissions | array[string] | False | | | An array of permissions representing a set of resources and scopes the client is seeking access. The format could be `RESOURCE_ID#SCOPE_ID`, `RESOURCE_ID`, or `#SCOPE_ID`. Used when `lazy_load_paths` is `false`. See [obtaining permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions). |
| lazy_load_paths | boolean | False | `false` | | If `true`, require discovery or resource registration endpoint to dynamically resolve the request URI to resources. This requires the Plugin to obtain a separate access token for itself from the token endpoint. Make sure the `Service Accounts Enabled` option is checked in Keycloak to allow for client credentials grant, and that the issued access token contains the `resource_access` claim with the `uma_protection` role for the Plugin to query resources through the [Protection API](https://www.keycloak.org/docs/latest/authorization_services/index.html#authorization-services). |
| http_method_as_scope | boolean | False | `false` | | If `true`, use the HTTP method of the request as the scope to check whether access should be granted. When `lazy_load_paths` is `false`, the Plugin adds the mapped scope to any of the static permissions configured in the `permissions` attribute, even when they contain one or more scopes already. |
| timeout | integer | False | 3000 | >= 1 | Timeout in milliseconds for the HTTP connection with the identity provider. |
| access_token_expires_in | integer | False | 300 | >= 1 | Lifetime of the access token in seconds if no `expires_in` attribute is present in the token endpoint response. |
| access_token_expires_leeway | integer | False | 0 | >= 0 | Expiration leeway in seconds for access token renewal. When set to a value greater than 0, token renewal will take place the configured amount of time before token expiration. |
| refresh_token_expires_in | integer | False | 3600 | > 0 | Expiration time of the refresh token in seconds. |
| refresh_token_expires_leeway | integer | False | 0 | >= 0 | Expiration leeway in seconds for refresh token renewal. When set to a value greater than 0, token renewal will take place the configured amount of time before token expiration. |
| ssl_verify | boolean | False | `true` | | If `true`, verify the OpenID provider's SSL certificates. |
| cache_ttl_seconds | integer | False | 86400 | > 0 | TTL in seconds for the Plugin to cache discovery document and access tokens. |
| keepalive | boolean | False | `true` | | If `true`, enable HTTP keep-alive to keep connections open after use. Set to `true` if you are expecting a lot of requests to Keycloak. |
| keepalive_timeout | integer | False | 60000 | >= 1000 | Idle time after which the established HTTP connections will be closed. |
| keepalive_pool | integer | False | 5 | >= 1 | Maximum number of connections in the connection pool. |
| access_denied_redirect_uri | string | False | | | URI to redirect the user to instead of returning an error message like `"error_description":"not_authorized"` when access is denied. |
| password_grant_token_generation_incoming_uri | string | False | | | The URI incoming requests hit to generate a token using the password grant, for example, `/api/token`. If the incoming request's URI matches the configured value, the request method is POST, and `Content-Type` is `application/x-www-form-urlencoded`, a token is generated at the `token_endpoint`. |

NOTE: `encrypt_fields = {"client_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Examples

The examples below demonstrate how you can configure `authz-keycloak` for different scenarios.

To follow along, complete the [preliminary setups](#set-up-keycloak) for Keycloak.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
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

Save the Keycloak IP to an environment variable:

```shell
KEYCLOAK_IP=192.168.42.145    # replace with your host IP
```

Navigate to `http://localhost:8080` in a browser and click **Administration Console**. Enter the administrator username `quickstart-admin` and password `quickstart-admin-pass` to sign in.

#### Create a Realm

In the left menu, hover over **Master**, and select **Add realm** in the dropdown. Enter the realm name `quickstart-realm` and click **Create**.

#### Create a Client

Click **Clients** > **Create** to open the **Add Client** page. Enter **Client ID** as `apisix-quickstart-client`, keep the **Client Protocol** as `openid-connect`, and click **Save**.

After redirecting to the detailed page, select `confidential` as the **Access Type**. Enter wildcard `*` in **Valid Redirect URIs** for simplicity.

Enable authorization for the Client, which also enables service accounts with the `uma_protection` role automatically. Click **Save**.

#### Save Client ID and Secret

Click **Clients** > `apisix-quickstart-client` > **Credentials**, and copy the Client secret from **Secret**.

Save the OIDC Client ID and secret to environment variables:

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

Save the access token to an environment variable:

```shell
ACCESS_TOKEN=<your_access_token>  # replace with the access_token value from the response
```

### Use Lazy Load Path and Resource Registration Endpoint

The following example demonstrates how you can configure the Plugin to dynamically resolve the request URI to resource(s) using the resource registration endpoint instead of static permissions.

Create a Route with the `authz-keycloak` Plugin:

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /anything
        plugins:
          authz-keycloak:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: true
        resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
        discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
        client_id: "apisix-quickstart-client"
        client_secret: "<OIDC_CLIENT_SECRET>"
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ Set `lazy_load_paths` to `true` to dynamically resolve the request URI to resources.

❷ Set `resource_registration_endpoint` to Keycloak's UMA-compliant resource registration endpoint. Required when `lazy_load_paths` is `true`.

❸ Set `discovery` to the discovery document endpoint of Keycloak authorization services.

❹ Set `client_id` to the Client ID created previously.

❺ Set `client_secret` to the Client secret created previously. Required when `lazy_load_paths` is `true`.

Send a request to the Route:

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

The following example demonstrates how you can configure Keycloak for scope-based permission associated with a Client scope policy, and configure the `authz-keycloak` Plugin to use static permissions.

#### Create Scope in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Authorization Scopes**, and click **Create**. Enter scope name `access` and click **Save**.

#### Create Resource in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Resources** and click **Create**. Enter resource name `httpbin-anything`, URI `/anything`, scope `access`, and click **Save**.

#### Create Client Scope in Keycloak

Go to **Client Scopes** and click **Create**. Enter scope name `httpbin-access` and click **Save**.

#### Create Policy in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Policies** > **Create Policies** and select **Client Scope**. Enter policy name `access-client-scope-policy` for Client scope `httpbin-access`, check **Required**, and click **Save**.

#### Create Permission in Keycloak

Go to **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Permissions** > **Create Permissions** and select **Scope-Based**. Enter permission name `access-scope-perm`, select scope `access`, apply policy `access-client-scope-policy`, and click **Save**.

#### Assign Client Scope

Go to **Clients** > **`apisix-quickstart-client`** > **Client Scopes** and add `httpbin-access` to the default Client scopes.

#### Configure APISIX

Create a Route with the `authz-keycloak` Plugin:

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /anything
        plugins:
          authz-keycloak:
            lazy_load_paths: false
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            permissions:
              - "httpbin-anything#access"
            client_id: "apisix-quickstart-client"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: false
        discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
        permissions:
          - "httpbin-anything#access"
        client_id: "apisix-quickstart-client"
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: false
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            permissions:
              - "httpbin-anything#access"
            client_id: "apisix-quickstart-client"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ Set `lazy_load_paths` to `false` to use static permissions.

❷ Set `discovery` to the discovery document endpoint of Keycloak authorization services.

❸ Set `permissions` to resource `httpbin-anything` and scope `access`.

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

You should see an `HTTP/1.1 200 OK` response. If you remove the Client scope `httpbin-access` for `apisix-quickstart-client`, you should receive a `401 Unauthorized` response.

### Generate Token with Password Grant

The following example demonstrates how you can generate a token using the password grant at a custom endpoint.

#### Create User in Keycloak

Go to **Users** > **Add user**, enter username `quickstart-user`, and click **Save**. Click **Credentials**, set password `quickstart-user-pass`, switch **Temporary** to `OFF`, and click **Set Password**.

#### Configure APISIX

Create a Route with the `authz-keycloak` Plugin:

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /api/*
        plugins:
          authz-keycloak:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
            token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
            password_grant_token_generation_incoming_uri: "/api/token"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: true
        resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
        client_id: "apisix-quickstart-client"
        client_secret: "<OIDC_CLIENT_SECRET>"
        token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
        password_grant_token_generation_incoming_uri: "/api/token"
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /api/*
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
            token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
            password_grant_token_generation_incoming_uri: "/api/token"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ Set `token_endpoint` to the Keycloak token endpoint. Required when a discovery document is not provided.

❷ Set `password_grant_token_generation_incoming_uri` to a custom URI path from which users can obtain tokens.

Send a request to the configured token endpoint using the POST method with `application/x-www-form-urlencoded` as the `Content-Type`:

```shell
OIDC_USER=quickstart-user
OIDC_PASSWORD=quickstart-user-pass

curl "http://127.0.0.1:9080/api/token" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d 'username='$OIDC_USER'' \
  -d 'password='$OIDC_PASSWORD''
```

You should see a JSON response with the access token.
