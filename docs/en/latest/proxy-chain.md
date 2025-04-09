# Proxy Chain Plugin for APISIX

The `proxy-chain` plugin for APISIX allows you to chain multiple upstream service calls in a sequence, passing data between them as needed. This is particularly useful for workflows where a request needs to interact with multiple services before returning a final response to the client.

## Features
- Chain multiple upstream service calls in a defined order.
- Pass custom headers (e.g., authentication tokens) between services.
- Flexible configuration for service endpoints and HTTP methods.

---

## Installation

### Docker

#### Prerequisites
- Docker installed on your system.
- APISIX version 3.0 or higher.

#### Steps
1. **Prepare the Plugin File**:
    - Place the `proxy-chain.lua` file in a local directory, e.g., `./plugins/`.

2. **Create a Dockerfile**:
    - Create a `Dockerfile` in your project directory:
      ```Dockerfile
      FROM apache/apisix:3.11.0-debian
      USER root
      COPY ./plugins/proxy-chain.lua /usr/local/apisix/apisix/plugins/proxy-chain.lua
      RUN chown -R apisix:apisix /usr/local/apisix/apisix/plugins/proxy-chain.lua
      CMD ["apisix", "start"]
      ```

3. **Build and Run**:
    - Build the Docker image and run it using `docker-compose` or directly:
      ```bash
      docker build -t apisix-with-proxy-chain .
      docker run -d -p 9080:9080 -p 9180:9180 apisix-with-proxy-chain
      ```
    - Alternatively, use a `docker-compose.yml`:
      ```yaml
      version: "3"
      services:
        apisix:
          image: apisix-with-proxy-chain
          build:
            context: .
            dockerfile: Dockerfile
          ports:
            - "9080:9080"
            - "9180:9180"
      ```
      ```bash
      docker-compose up -d --build
      ```

4. **Reload APISIX**:
    - Ensure the plugin is loaded:
      ```bash
      docker exec <container_name> apisix reload
      ```

### Kubernetes

#### Prerequisites
- A Kubernetes cluster (e.g., Minikube, GKE, EKS).
- `kubectl` configured to interact with your cluster.
- Helm (optional, for easier deployment).

#### Steps
1. **Prepare the Plugin File**:
    - Place `proxy-chain.lua` in a local directory, e.g., `./plugins/`.

2. **Create a ConfigMap**:
    - Define a ConfigMap to include the plugin file:
      ```yaml
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: apisix-plugins
      data:
        proxy-chain.lua: |
          -- Content of proxy-chain.lua goes here
          -- (Paste the entire Lua code here)
      ```

3. **Deploy APISIX with Custom Plugin**:
    - Use a Helm chart or a custom manifest. Here’s an example with a manifest:
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: apisix
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: apisix
        template:
          metadata:
            labels:
              app: apisix
          spec:
            containers:
            - name: apisix
              image: apache/apisix:3.11.0-debian
              ports:
              - containerPort: 9080
              - containerPort: 9180
              volumeMounts:
              - name: plugins-volume
                mountPath: /usr/local/apisix/apisix/plugins/proxy-chain.lua
                subPath: proxy-chain.lua
            volumes:
            - name: plugins-volume
              configMap:
                name: apisix-plugins
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: apisix-service
      spec:
        ports:
        - port: 9080
          targetPort: 9080
          name: gateway
        - port: 9180
          targetPort: 9180
          name: admin
        selector:
          app: apisix
        type: LoadBalancer
      ```
    - Apply the manifests:
      ```bash
      kubectl apply -f configmap.yaml
      kubectl apply -f apisix-deployment.yaml
      ```

4. **Reload APISIX**:
    - Access the APISIX Admin API to reload:
      ```bash
      kubectl exec -it <apisix-pod-name> -- apisix reload
      ```

---

## Configuration

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

## Attributes
| Name           | Type   | Required | Default | Description                                      |
|----------------|--------|----------|---------|--------------------------------------------------|
| services       | array  | Yes      | -       | List of upstream services to chain.              |
| services.uri   | string | Yes      | -       | URI of the upstream service.                     |
| services.method| string | Yes      | -       | HTTP method (e.g., "GET", "POST").              |
| token_header   | string | No       | -       | Custom header to pass a token between services.  |
