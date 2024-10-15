---
title: Kubernetes
keywords:
  - Kubernetes
  - Apache APISIX
  - Service discovery
  - Cluster
  - API Gateway
description: This article introduce how to perform service discovery based on Kubernetes in Apache APISIX and summarize related issues.
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

## Summary

The [_Kubernetes_](https://kubernetes.io/) service discovery [_List-Watch_](https://kubernetes.io/docs/reference/using-api/api-concepts/) real-time changes of [_Endpoints_](https://kubernetes.io/docs/concepts/services-networking/service/) resources, then store theirs value into `ngx.shared.DICT`.

Discovery also provides a node query interface in accordance with the [_APISIX Discovery Specification_](../discovery.md).

## How To Use

Kubernetes service discovery both support single-cluster and multi-cluster modes, applicable to the case where the service is distributed in single or multiple Kubernetes clusters.

### Single-Cluster Mode Configuration

A detailed configuration for single-cluster mode Kubernetes service discovery is as follows:

```yaml
discovery:
  kubernetes:
    service:
      # apiserver schema, options [http, https]
      schema: https #default https

      # apiserver host, options [ipv4, ipv6, domain, environment variable]
      host: ${KUBERNETES_SERVICE_HOST} #default ${KUBERNETES_SERVICE_HOST}

      # apiserver port, options [port number, environment variable]
      port: ${KUBERNETES_SERVICE_PORT}  #default ${KUBERNETES_SERVICE_PORT}

    client:
      # serviceaccount token or token_file
      token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

      #token: |-
       # eyJhbGciOiJSUzI1NiIsImtpZCI6Ikx5ME1DNWdnbmhQNkZCNlZYMXBsT3pYU3BBS2swYzBPSkN3ZnBESGpkUEEif
       # 6Ikx5ME1DNWdnbmhQNkZCNlZYMXBsT3pYU3BBS2swYzBPSkN3ZnBESGpkUEEifeyJhbGciOiJSUzI1NiIsImtpZCI

    default_weight: 50 # weight assigned to each discovered endpoint. default 50, minimum 0

    # kubernetes discovery support namespace_selector
    # you can use one of [equal, not_equal, match, not_match] filter namespace
    namespace_selector:
      # only save endpoints with namespace equal default
      equal: default

      # only save endpoints with namespace not equal default
      #not_equal: default

      # only save endpoints with namespace match one of [default, ^my-[a-z]+$]
      #match:
       #- default
       #- ^my-[a-z]+$

      # only save endpoints with namespace not match one of [default, ^my-[a-z]+$ ]
      #not_match:
       #- default
       #- ^my-[a-z]+$

    # kubernetes discovery support label_selector
    # for the expression of label_selector, please refer to https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
    label_selector: |-
      first="a",second="b"

    # reserved lua shared memory size,1m memory can store about 1000 pieces of endpoint
    shared_size: 1m #default 1m

    # if watch_endpoint_slices setting true, watch apiserver with endpointslices instead of endpoints
    watch_endpoint_slices: false #default false
```

If the Kubernetes service discovery runs inside a pod, you can use minimal configuration:

```yaml
discovery:
  kubernetes: { }
```

If the Kubernetes service discovery runs outside a pod, you need to create or select a specified [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/), then get its token value, and use following configuration:

```yaml
discovery:
  kubernetes:
    service:
      schema: https
      host: # enter apiserver host value here
      port: # enter apiserver port value here
    client:
      token: # enter serviceaccount token value here
      #token_file: # enter file path here
```

### Single-Cluster Mode Query Interface

The Kubernetes service discovery provides a query interface in accordance with the [_APISIX Discovery Specification_](../discovery.md).

**function:**
 nodes(service_name)

**description:**
  nodes() function attempts to look up the ngx.shared.DICT for nodes corresponding to service_name, \
  service_name should match pattern: _[namespace]/[name]:[portName]_

  + namespace: The namespace where the Kubernetes endpoints is located

  + name: The name of the Kubernetes endpoints

  + portName: The `ports.name` value in the Kubernetes endpoints, if there is no `ports.name`, use `targetPort`, `port` instead. If `ports.name` exists, then port number cannot be used.

**return value:**
  if the Kubernetes endpoints value is as follows:

  ```yaml
  apiVersion: v1
  kind: Endpoints
  metadata:
    name: plat-dev
    namespace: default
  subsets:
    - addresses:
        - ip: "10.5.10.109"
        - ip: "10.5.10.110"
      ports:
        - port: 3306
          name: port
  ```

  a nodes("default/plat-dev:port") call will get follow result:

  ```
   {
       {
           host="10.5.10.109",
           port= 3306,
           weight= 50,
       },
       {
           host="10.5.10.110",
           port= 3306,
           weight= 50,
       },
   }
  ```

### Multi-Cluster Mode Configuration

A detailed configuration for multi-cluster mode Kubernetes service discovery is as follows:

```yaml
discovery:
  kubernetes:
  - id: release  # a custom name refer to the cluster, pattern ^[a-z0-9]{1,8}
    service:
      # apiserver schema, options [http, https]
      schema: https #default https

      # apiserver host, options [ipv4, ipv6, domain, environment variable]
      host: "1.cluster.com"

      # apiserver port, options [port number, environment variable]
      port: "6443"

    client:
      # serviceaccount token or token_file
      token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

      #token: |-
       # eyJhbGciOiJSUzI1NiIsImtpZCI6Ikx5ME1DNWdnbmhQNkZCNlZYMXBsT3pYU3BBS2swYzBPSkN3ZnBESGpkUEEif
       # 6Ikx5ME1DNWdnbmhQNkZCNlZYMXBsT3pYU3BBS2swYzBPSkN3ZnBESGpkUEEifeyJhbGciOiJSUzI1NiIsImtpZCI

    default_weight: 50 # weight assigned to each discovered endpoint. default 50, minimum 0

    # kubernetes discovery support namespace_selector
    # you can use one of [equal, not_equal, match, not_match] filter namespace
    namespace_selector:
      # only save endpoints with namespace equal default
      equal: default

      # only save endpoints with namespace not equal default
      #not_equal: default

      # only save endpoints with namespace match one of [default, ^my-[a-z]+$]
      #match:
       #- default
       #- ^my-[a-z]+$

      # only save endpoints with namespace not match one of [default, ^my-[a-z]+$]
      #not_match:
       #- default
       #- ^my-[a-z]+$

    # kubernetes discovery support label_selector
    # for the expression of label_selector, please refer to https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
    label_selector: |-
      first="a",second="b"

    # reserved lua shared memory size,1m memory can store about 1000 pieces of endpoint
    shared_size: 1m #default 1m

    # if watch_endpoint_slices setting true, watch apiserver with endpointslices instead of endpoints
    watch_endpoint_slices: false #default false
```

Multi-Kubernetes service discovery does not fill default values for service and client fields, you need to fill them according to the cluster configuration.

### Multi-Cluster Mode Query Interface

The Kubernetes service discovery provides a query interface in accordance with the [_APISIX Discovery Specification_](../discovery.md).

**function:**
nodes(service_name)

**description:**
nodes() function attempts to look up the ngx.shared.DICT for nodes corresponding to service_name, \
service_name should match pattern: _[id]/[namespace]/[name]:[portName]_

+ id: value defined in service discovery configuration

+ namespace: The namespace where the Kubernetes endpoints is located

+ name: The name of the Kubernetes endpoints

+ portName: The `ports.name` value in the Kubernetes endpoints, if there is no `ports.name`, use `targetPort`, `port` instead. If `ports.name` exists, then port number cannot be used.

**return value:**
if the Kubernetes endpoints value is as follows:

  ```yaml
  apiVersion: v1
  kind: Endpoints
  metadata:
    name: plat-dev
    namespace: default
  subsets:
    - addresses:
        - ip: "10.5.10.109"
        - ip: "10.5.10.110"
      ports:
        - port: 3306
          name: port
  ```

a nodes("release/default/plat-dev:port") call will get follow result:

  ```
   {
       {
           host="10.5.10.109",
           port= 3306,
           weight= 50,
       },
       {
           host="10.5.10.110",
           port= 3306,
           weight= 50,
       },
   }
  ```

## Q&A

**Q: Why only support configuration token to access _Kubernetes APIServer_?**

A: Usually, we will use three ways to complete the authentication of _Kubernetes APIServer_:

+ mTLS
+ Token
+ Basic authentication

Because lua-resty-http does not currently support mTLS, and basic authentication is not recommended, so currently only the token authentication method is implemented.

**Q: APISIX inherits Nginx's multiple process model, does it mean that each nginx worker process will [_List-Watch_](https://kubernetes.io/docs/reference/using-api/api-concepts/) kubernetes endpoints resources?**

A: The Kubernetes service discovery only uses privileged processes to [_List-Watch_](https://kubernetes.io/docs/reference/using-api/api-concepts/) Kubernetes endpoints resources, then store theirs value into `ngx.shared.DICT`, worker processes get results by querying `ngx.shared.DICT`.

**Q: What permissions do [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) require?**

A: ServiceAccount requires the permissions of cluster-level [ get, list, watch ] endpoints and endpointslices resources, the declarative definition is as follows:

```yaml
kind: ServiceAccount
apiVersion: v1
metadata:
 name: apisix-test
 namespace: default
---

kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: apisix-test
rules:
  - apiGroups: [ "" ]
    resources: [ endpoints]
    verbs: [ get,list,watch ]
  - apiGroups: [ "discovery.k8s.io" ]
    resources: [ endpointslices ]
    verbs: [ get,list,watch ]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
 name: apisix-test
roleRef:
 apiGroup: rbac.authorization.k8s.io
 kind: ClusterRole
 name: apisix-test
subjects:
 - kind: ServiceAccount
   name: apisix-test
   namespace: default
```

**Q: How to get [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) token value?**

A: Assume your [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) located in namespace apisix and name is Kubernetes-discovery, you can use the following steps to get token value.

 1. Get secret name. You can execute the following command, the output of the first column is the secret name we want:

 ```shell
 kubectl -n apisix get secrets | grep kubernetes-discovery
 ```

 2. Get token value. Assume secret resources name is kubernetes-discovery-token-c64cv, you can execute the following command, the output is the service account token value we want:

 ```shell
 kubectl -n apisix get secret kubernetes-discovery-token-c64cv -o jsonpath={.data.token} | base64 -d
 ```

## Debugging API

It also offers control api for debugging.

### Memory Dump API

To query/list the nodes discoverd by kubernetes discovery, you can query the /v1/discovery/kubernetes/dump control API endpoint like so:

```shell
GET /v1/discovery/kubernetes/dump
```

Which will yield the following response:

```
{
  "endpoints": [
    {
      "endpoints": [
        {
          "value": "{\"https\":[{\"host\":\"172.18.164.170\",\"port\":6443,\"weight\":50},{\"host\":\"172.18.164.171\",\"port\":6443,\"weight\":50},{\"host\":\"172.18.164.172\",\"port\":6443,\"weight\":50}]}",
          "name": "default/kubernetes"
        },
        {
          "value": "{\"metrics\":[{\"host\":\"172.18.164.170\",\"port\":2379,\"weight\":50},{\"host\":\"172.18.164.171\",\"port\":2379,\"weight\":50},{\"host\":\"172.18.164.172\",\"port\":2379,\"weight\":50}]}",
          "name": "kube-system/etcd"
        },
        {
          "value": "{\"http-85\":[{\"host\":\"172.64.89.2\",\"port\":85,\"weight\":50}]}",
          "name": "test-ws/testing"
        }
      ],
      "id": "first"
    }
  ],
  "config": [
    {
      "default_weight": 50,
      "id": "first",
      "client": {
        "token": "xxx"
      },
      "service": {
        "host": "172.18.164.170",
        "port": "6443",
        "schema": "https"
      },
      "shared_size": "1m"
    }
  ]
}
```
