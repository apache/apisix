---
title: Proxy Chain Plugin for APISIX
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
[proxy-chain](https://github.com/apache/apisix) is a plugin for [APISIX](https://github.com/apache/apisix) that allows you to chain multiple upstream service calls in sequence, passing data between them as needed. This is particularly useful for workflows where a request must interact with several services before returning a final response to the client.

## Description
proxy-chain is a custom plugin for Apache APISIX that enables chaining multiple upstream service calls in a specific sequence. This is useful when a single client request needs to interact with multiple services before generating the final response.
This plugin allows APISIX to execute multiple HTTP calls to different upstream services, one after another. The output of one call can be used by the next, enabling complex workflows (e.g., collecting user info, validating payments, updating inventory).

### Typical use cases:
- Multi-step workflows like checkout flows
- Aggregating data from multiple internal services
- Orchestrating legacy APIs

## Features
- Chain multiple upstream service calls in a defined order.
- Pass custom headers (e.g., authentication tokens) between services.
- Flexible configuration for service endpoints and HTTP methods.


## Attributes

| Name           | Type   | Required | Default | Description                                      |
|----------------|--------|----------|---------|--------------------------------------------------|
| services       | array  | Yes      | -       | List of upstream services to chain.              |
| services.uri   | string | Yes      | -       | URI of the upstream service.                     |
| services.method| string | Yes      | -       | HTTP method (e.g., "GET", "POST").              |
| token_header   | string | No       | -       | Custom header to pass a token between services.  |


---

## Enable Plugin
Use the Admin API to bind the plugin to a route:

### Docker

#### Configuration Steps

1. **Add to Route**:
    - Use the APISIX Admin API to configure a route:

      ```bash

      curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/24 \
        -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
        -H 'Content-Type: application/json' \
        -d '{
          "uri": "/api/v1/checkout",
          "methods": ["POST"],
          "plugins": {
            "proxy-chain": {
              "services": [
                {
                  "uri": "http://customer_service/api/v1/user",
                  "method": "POST"
                }
              ]
            }
          },
          "upstream_id": "550932803756229477"
        }'

      ```

2. **Verify**:
    - Test the endpoint:

      ```bash

      curl -X POST http://<external-ip>/v1/checkout

      ```

### Kubernetes

#### Configuration Steps

1. **Add to Route**:
    - Assuming APISIX Ingress Controller is installed, use a custom resource (CRD) or Admin API:

      ```yaml

      apiVersion: apisix.apache.org/v2
      kind: ApisixRoute
      metadata:
        name: checkout-route
      spec:
        http:
        - name: checkout
          match:
            paths:
            - /v1/checkout
            methods:
            - POST
          backends:
            - serviceName: upstream-service
              servicePort: 80
          plugins:
          - name: proxy-chain
            enable: true
            config:
              services:
              - uri: "http://customer_service/api/v1/user"
                method: "POST"

        ```

    - Apply the CRD:

      ```bash

      kubectl apply -f route.yaml

      ```

    - Alternatively, use the Admin API via port-forwarding:

      ```bash

      kubectl port-forward service/apisix-service 9180:9180
      curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/24 \
        -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
        -H 'Content-Type: application/json' \
        -d '{
          "uri": "/offl/v1/checkout",
          "methods": ["POST"],
          "plugins": {
            "proxy-chain": {
              "services": [
                {
                  "uri": "http://customer_service/api/v1/user",
                  "method": "POST"
                }
              ],
            }
          },
          "upstream_id": "550932803756229477"
        }'

      ```

2. **Verify**:
    - Test the endpoint (assuming a LoadBalancer or Ingress):

      ```bash

      curl -X POST http://<external-ip>/v1/checkout

      ```

---

## Example usage

Once the plugin is enabled on a route, you can send a request like this:

```bash

curl -X POST http://127.0.0.1:9080/v1/checkout \
  -H "Content-Type: application/json" \
  -d '{"cart_id": "abc123"}'

```

This will trigger the sequence of service calls defined in services.


## Delete Plugin

To disable the plugin for a route, remove it from the plugin list via Admin API:

```bash

curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/checkout \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H 'Content-Type: application/json' \
  -d '{
    "uri": "/v1/checkout",
    "methods": ["POST"],
    "plugins": {},
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'

```


