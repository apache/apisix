---
title: Open Policy Agent (opa)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Open Policy Agent
  - opa
description: The opa plugin integrates with Open Policy Agent, enabling unified policy definition and enforcement for authorization in API operations.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/opa" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `opa` Plugin supports the integration with [Open Policy Agent (OPA)](https://www.openpolicyagent.org), a unified policy engine and framework that helps define and enforce authorization policies. Authorization logic is defined in [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/) and stored in OPA.

Once configured, the OPA engine will evaluate the client request to a protected Route to determine whether the request should have access to the Upstream resource based on the defined policies.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| host | string | True | | | Address of the OPA server. |
| policy | string | True | | | Policy to evaluate. For example, if you would like to evaluate all rules in a package called `rbac`, configure the policy to be `rbac`. If you would like to evaluate specific rule(s) in a package, you can specify the rule name behind the package, such as `rbac/allow`. |
| ssl_verify | boolean | False | true | | If true, verify the OPA server's SSL certificate. |
| timeout | integer | False | 3000 | [1, 60000] | Timeout for the HTTP call in milliseconds. |
| keepalive | boolean | False | true | | If true, keep the connection alive for multiple requests. |
| keepalive_timeout | integer | False | 60000 | >= 1000 | Idle time in milliseconds after which the connection is closed. |
| keepalive_pool | integer | False | 5 | >= 1 | The number of idle connections. |
| with_route | boolean | False | | | If true, send information of the current Route. |
| with_service | boolean | False | | | If true, send information of the current Service. |
| with_consumer | boolean | False | | | If true, send information of the current Consumer. Note that the Consumer information may include sensitive information such as the API key. Only set this option to `true` if you are sure it is safe to do so. |
| send_headers_upstream | array[string] | False | | >= 1 item | List of header names to forward from the OPA response to the Upstream service when the request is allowed. |

## Data Definition

### APISIX to OPA Service

The JSON below shows the data sent to the OPA service by APISIX:

```json
{
    "type": "http",
    "request": {
        "scheme": "http",
        "path": "\/get",
        "headers": {
            "user-agent": "curl\/7.68.0",
            "accept": "*\/*",
            "host": "127.0.0.1:9080"
        },
        "query": {},
        "port": 9080,
        "method": "GET",
        "host": "127.0.0.1"
    },
    "var": {
        "timestamp": 1701234567,
        "server_addr": "127.0.0.1",
        "server_port": "9080",
        "remote_port": "port",
        "remote_addr": "ip address"
    },
    "route": {},
    "service": {},
    "consumer": {}
}
```

Each of these keys are explained below:

- `type` indicates the request type (`http` or `stream`).
- `request` is used when the `type` is `http` and contains the basic request information (URL, headers etc).
- `var` contains the basic information about the requested connection (IP, port, request timestamp etc).
- `route`, `service` and `consumer` contains the same data as stored in APISIX and are only sent if the `opa` Plugin is configured on these objects.

### OPA Service to APISIX

The JSON below shows the response from the OPA service to APISIX:

```json
{
    "result": {
        "allow": true,
        "reason": "test",
        "headers": {
            "an": "header"
        },
        "status_code": 401
    }
}
```

The keys in the response are explained below:

- `allow` is indispensable and indicates whether the request is allowed to be forwarded through APISIX.
- `reason`, `headers`, and `status_code` are optional and are only returned when you configure a custom response.

## Examples

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

Before proceeding, you should have a running OPA server. Start one using Docker or deploy it to Kubernetes:

<Tabs
groupId="opa-setup"
defaultValue="docker"
values={[
{label: 'Docker', value: 'docker'},
{label: 'Kubernetes', value: 'kubernetes'}
]}>

<TabItem value="docker">

```shell
docker run -d --name opa-server -p 8181:8181 openpolicyagent/opa:1.6.0 run --server --addr :8181 --log-level debug
```

To verify that the OPA server is installed and the port is exposed properly, run:

```shell
curl http://127.0.0.1:8181 | grep Version
```

You should see a response similar to the following:

```text
Version: 1.6.0
```

</TabItem>

<TabItem value="kubernetes">

Create a Deployment and Service for OPA in your cluster:

```yaml title="opa-server.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: aic
  name: opa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
    spec:
      containers:
        - name: opa
          image: openpolicyagent/opa:1.6.0
          args:
            - run
            - --server
            - --addr=:8181
            - --log-level=debug
          ports:
            - containerPort: 8181
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: opa
spec:
  selector:
    app: opa
  ports:
    - port: 8181
      targetPort: 8181
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-server.yaml
```

Wait for the OPA pod to be ready. Once ready, the OPA server will be available within the cluster at `http://opa.aic.svc.cluster.local:8181`. To push policies to it from outside the cluster, set up a port-forward:

```shell
kubectl port-forward -n aic svc/opa 8181:8181 &
```

</TabItem>

</Tabs>

### Implement a Basic Policy

The following example implements a basic authorization policy in OPA to allow only GET requests.

Create an OPA policy that only allows HTTP GET requests:

```shell
curl "http://127.0.0.1:8181/v1/policies/getonly" -X PUT  \
  -H "Content-Type: text/plain" \
  -d '
package getonly

default allow = false

allow if {
    input.request.method == "GET"
}'
```

Create a Route with the `opa` Plugin:

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
    "id": "opa-route",
    "uri": "/anything",
    "plugins": {
      "opa": {
        "host": "http://127.0.0.1:8181",
        "policy": "getonly"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Update `host` to your OPA server address. The `policy` is set to `getonly`.

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: getonly
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Update `host` to your OPA server address. The `policy` is set to `getonly`.

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

```yaml title="opa-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: opa-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: getonly
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="opa-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: getonly
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

To verify the policy, send a GET request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send another request to the Route using PUT:

```shell
curl -i "http://127.0.0.1:9080/anything" -X PUT
```

You should receive an `HTTP/1.1 403 Forbidden` response.

### Understand Data Format

The following example helps you understand the data and the format APISIX pushes to OPA to support authorization logic writing. The example continues with the policy and the Route in the [last example](#implement-a-basic-policy).

Now, update the Plugin on the previously created Route to include Route information:

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
curl "http://127.0.0.1:9180/apisix/admin/routes/opa-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "opa": {
        "with_route": true
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Update `adc.yaml` to add `with_route: true`:

```yaml title="adc.yaml"
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: getonly
            with_route: true
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

Update `opa-ic.yaml` to add `with_route: true`:

```yaml title="opa-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: opa-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: getonly
        with_route: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the updated configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

Update `opa-ic.yaml` to add `with_route: true`:

```yaml title="opa-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: getonly
            with_route: true
```

Apply the updated configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

In the OPA server log (with `--log-level debug`), the `req_body` will now include Route information in addition to the request and var fields.

### Return Custom Response

The following example demonstrates how you can return a custom response code and message when the request is unauthorized.

Create an OPA policy that only allows HTTP GET requests and returns `302` with a custom message when the request is unauthorized:

```shell
curl "127.0.0.1:8181/v1/policies/customresp" -X PUT \
  -H "Content-Type: text/plain" \
  -d '
package customresp

default allow = false

allow if {
  input.request.method == "GET"
}

reason := "The resource has temporarily moved. Please follow the new URL." if {
  not allow
}

headers := {
  "Location": "http://example.com/auth"
} if {
  not allow
}

status_code := 302 if {
  not allow
}
'
```

Create a Route with the `opa` Plugin:

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
    "id": "opa-route",
    "uri": "/anything",
    "plugins": {
      "opa": {
        "host": "http://192.168.2.104:8181",
        "policy": "customresp"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: customresp
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

```yaml title="opa-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: opa-customresp-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: customresp
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-customresp-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="opa-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: customresp
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a GET request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a POST request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST
```

You should receive an `HTTP/1.1 302 Moved Temporarily` response:

```text
HTTP/1.1 302 Moved Temporarily
...
Location: http://example.com/auth

The resource has temporarily moved. Please follow the new URL.
```

### Implement RBAC

The following example demonstrates how to implement authentication and RBAC using the `jwt-auth` and `opa` Plugins. You will be implementing RBAC logics such that:

* An `user` role can only read the Upstream resources.
* An `admin` role can read and write the Upstream resources.

Create an OPA policy for RBAC of two example Consumers, where `john` has the `user` role and `jane` has the `admin` role:

```shell
curl "http://127.0.0.1:8181/v1/policies/rbac" -X PUT \
  -H "Content-Type: text/plain" \
  -d '
package rbac

# Assign roles to users
user_roles := {
  "john": ["user"],
  "jane": ["admin"]
}

# Map permissions to HTTP methods
permission_methods := {
  "read": "GET",
  "write": "POST"
}

# Assign role permissions
role_permissions := {
  "user": ["read"],
  "admin": ["read", "write"]
}

# Get JWT authorization token
bearer_token := t if {
  t := input.request.headers.authorization
}

# Decode the token to get role and permission
token := {"payload": payload} if {
  [_, payload, _] := io.jwt.decode(bearer_token)
}

# Normalize permission to a list
normalized_permissions := ps if {
  ps := token.payload.permission
  not is_string(ps)
}

normalized_permissions := [ps] if {
  ps := token.payload.permission
  is_string(ps)
}

# Implement RBAC logic
default allow = false

allow if {
  # Look up the list of roles for the user
  roles := user_roles[input.consumer.username]

  # For each role in that list
  r := roles[_]

  # Look up the permissions list for the role
  permissions := role_permissions[r]

  # For each permission
  p := permissions[_]

  # Check if the permission matches the request method
  permission_methods[p] == input.request.method

  # Check if the normalized permissions include the permission
  p in normalized_permissions
}
'
```

Create two Consumers `john` and `jane` in APISIX and configure their `jwt-auth` Credentials:

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
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT -d '
{
  "username": "john"
}'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT -d '
{
  "username": "jane"
}'
```

Configure the `jwt-auth` Credentials for the Consumers, using the default algorithm `HS256`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "john-key",
        "secret": "john-hs256-secret-that-is-very-long"
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jane-key",
        "secret": "jane-hs256-secret-that-is-very-long"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: cred-john-jwt-auth
        type: jwt-auth
        config:
          key: john-key
          secret: john-hs256-secret-that-is-very-long
  - username: jane
    credentials:
      - name: cred-jane-jwt-auth
        type: jwt-auth
        config:
          key: jane-key
          secret: jane-hs256-secret-that-is-very-long
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

```yaml title="opa-consumers-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: cred-john-jwt-auth
      config:
        key: john-key
        secret: john-hs256-secret-that-is-very-long
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jane
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: cred-jane-jwt-auth
      config:
        key: jane-key
        secret: jane-hs256-secret-that-is-very-long
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-consumers-ic.yaml
```

When using the Ingress Controller, APISIX prefixes Consumer names with the Kubernetes namespace. For example, a Consumer named `john` in the `aic` namespace becomes `aic_john`. Update the OPA RBAC policy to use the prefixed names accordingly.

</TabItem>

<TabItem value="apisix-ingress-controller">

The ApisixConsumer CRD has a known issue where `private_key` is incorrectly required during the configuration. This issue will be addressed in a future release. At the moment, the example cannot be completed with APISIX CRDs.

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Create a Route and configure the `jwt-auth` and `opa` Plugins:

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
    "id": "opa-route",
    "methods": ["GET", "POST"],
    "uris": ["/get","/post"],
    "plugins": {
      "jwt-auth": {},
      "opa": {
        "host": "http://192.168.2.104:8181",
        "policy": "rbac",
        "with_consumer": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Update `adc.yaml` to add the Route with `jwt-auth` and `opa` Plugins:

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: cred-john-jwt-auth
        type: jwt-auth
        config:
          key: john-key
          secret: john-hs256-secret-that-is-very-long
  - username: jane
    credentials:
      - name: cred-jane-jwt-auth
        type: jwt-auth
        config:
          key: jane-key
          secret: jane-hs256-secret-that-is-very-long
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /get
          - /post
        methods:
          - GET
          - POST
        plugins:
          jwt-auth: {}
          opa:
            host: "http://192.168.2.104:8181"
            policy: rbac
            with_consumer: true
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

```yaml title="opa-route-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: opa-rbac-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        _meta:
          disable: false
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: rbac
        with_consumer: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-rbac-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
          method: GET
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-rbac-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-rbac-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f opa-route-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

The ApisixConsumer CRD has a known issue where `private_key` is incorrectly required during the configuration. This issue will be addressed in a future release. At the moment, the example cannot be completed with APISIX CRDs.

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### Verify as `john`

To issue a JWT for `john`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the **Valid secret** section to be `john-hs256-secret-that-is-very-long`.
* Update payload with role `user`, permission `read`, and Consumer key `john-key`; as well as `exp` or `nbf` in UNIX timestamp.

Your payload should look similar to the following:

```json
{
  "role": "user",
  "permission": "read",
  "key": "john-key",
  "nbf": 1729132271
}
```

Copy the generated JWT and save to a variable:

```text
export john_jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciIsInBlcm1pc3Npb24iOiJyZWFkIiwia2V5Ijoiam9obi1rZXkiLCJuYmYiOjE3MjkxMzIyNzF9.rAHMTQfnnGFnKYc3am_lpE9pZ9E8EaOT_NBQ5Ss8pk4
```

Send a GET request to the Route with the JWT of `john`:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${john_jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a POST request to the Route with the same JWT:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -H "Authorization: ${john_jwt_token}"
```

You should receive an `HTTP/1.1 403 Forbidden` response.

#### Verify as `jane`

Similarly, to issue a JWT for `jane`, you could use [JWT.io's JWT encoder](https://jwt.io) or other utilities. If you are using [JWT.io's JWT encoder](https://jwt.io), do the following:

* Fill in `HS256` as the algorithm.
* Update the secret in the **Valid secret** section to be `jane-hs256-secret-that-is-very-long`.
* Update payload with role `admin`, permission `["read","write"]`, and Consumer key `jane-key`; as well as `exp` or `nbf` in UNIX timestamp.

Your payload should look similar to the following:

```json
{
  "role": "admin",
  "permission": ["read","write"],
  "key": "jane-key",
  "nbf": 1729132271
}
```

Copy the generated JWT and save to a variable:

```text
export jane_jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYWRtaW4iLCJwZXJtaXNzaW9uIjpbInJlYWQiLCJ3cml0ZSJdLCJrZXkiOiJqYW5lLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.meZ-AaGHUPwN_GvVOE3IkKuAJ1wqlCguaXf3gm3Ww8s
```

Send a GET request to the Route with the JWT of `jane`:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jane_jwt_token}"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a POST request to the Route with the same JWT:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -H "Authorization: ${jane_jwt_token}"
```

You should also receive an `HTTP/1.1 200 OK` response.
