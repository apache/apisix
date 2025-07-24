---
title: Kubernetes
keywords:
  - Kubernetes
  - Apache APISIX
  - 服务发现
  - 集群
  - API 网关
description: 本文将介绍如何在 Apache APISIX 中基于 Kubernetes 进行服务发现以及相关问题汇总。
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

## 基于 Kubernetes 的服务发现

Kubernetes 服务发现以 [_List-Watch_](https://kubernetes.io/docs/reference/using-api/api-concepts) 方式监听 [_Kubernetes_](https://kubernetes.io) 集群 [_Endpoints_](https://kubernetes.io/docs/concepts/services-networking/service) 资源的实时变化，并将其值存储到 ngx.shared.DICT 中。

同时遵循 [_APISIX Discovery 规范_](../discovery.md) 提供了节点查询接口。

## Kubernetes 服务发现的使用

目前 Kubernetes 服务发现支持单集群和多集群模式，分别适用于待发现的服务分布在单个或多个 Kubernetes 的场景。

### 单集群模式 Kubernetes 服务发现的配置格式

单集群模式 Kubernetes 服务发现的完整配置如下：

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

      # only save endpoints with namespace not match one of [default, ^my-[a-z]+$]
      #not_match:
       #- default
       #- ^my-[a-z]+$

    # kubernetes discovery support label_selector
    # for the expression of label_selector, please refer to https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
    label_selector: |-
      first="a",second="b"

    # reserved lua shared memory size, 1m memory can store about 1000 pieces of endpoint
    shared_size: 1m #default 1m

    # if watch_endpoint_slices setting true, watch apiserver with endpointslices instead of endpoints
    watch_endpoint_slices: false #default false
```

如果 Kubernetes 服务发现运行在 Pod 内，你可以使用如下最简配置：

```yaml
discovery:
  kubernetes: { }
```

如果 Kubernetes 服务发现运行在 Pod 外，你需要新建或选取指定的 [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/), 获取其 Token 值，然后使用如下配置：

```yaml
discovery:
  kubernetes:
    service:
      schema: https
      host: # enter apiserver host value here
      port: # enter apiServer port value here
    client:
      token: # enter serviceaccount token value here
      #token_file: # enter token file path here
```

### 单集群模式 Kubernetes 服务发现的查询接口

单集群模式 Kubernetes 服务发现遵循 [_APISIX Discovery 规范_](../discovery.md) 提供节点查询接口。

**函数：**
nodes(service_name)

**说明：**
service_name 必须满足格式：[namespace]/[name]:[portName]

+ namespace: Endpoints 所在的命名空间

+ name: Endpoints 的资源名

+ portName: Endpoints 定义包含的 `ports.name` 值，如果 Endpoints 没有定义 `ports.name`，请依次使用 `targetPort`, `port` 代替。设置了 `ports.name` 的情况下，不能使用后两者。

**返回值：**
以如下 Endpoints 为例：

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

nodes("default/plat-dev:port") 调用会得到如下的返回值：

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

### 多集群模式 Kubernetes 服务发现的配置格式

多集群模式 Kubernetes 服务发现的完整配置如下：

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

多集群模式 Kubernetes 服务发现没有为 `service` 和 `client` 域填充默认值，你需要根据集群配置情况自行填充。

### 多集群模式 Kubernetes 服务发现的查询接口

多集群模式 Kubernetes 服务发现遵循 [_APISIX Discovery 规范_](../discovery.md) 提供节点查询接口。

**函数：**
nodes(service_name)

**说明：**
service_name 必须满足格式：[id]/[namespace]/[name]:[portName]

+ id: Kubernetes 服务发现配置中定义的集群 id 值

+ namespace: Endpoints 所在的命名空间

+ name: Endpoints 的资源名

+ portName: Endpoints 定义包含的 `ports.name` 值，如果 Endpoints 没有定义 `ports.name`，请依次使用 `targetPort`, `port` 代替。设置了 `ports.name` 的情况下，不能使用后两者。

**返回值：**
以如下 Endpoints 为例：

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

nodes("release/default/plat-dev:port") 调用会得到如下的返回值：

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

**Q: 为什么只支持配置 token 来访问 Kubernetes APIServer?**

A: 一般情况下，我们有三种方式可以完成与 Kubernetes APIServer 的认证：

- mTLS
- Token
- Basic authentication

因为 lua-resty-http 目前不支持 mTLS, Basic authentication 不被推荐使用，所以当前只实现了 Token 认证方式。

**Q: APISIX 继承了 NGINX 的多进程模型，是否意味着每个 APISIX 工作进程都会监听 Kubernetes Endpoints？**

A: Kubernetes 服务发现只使用特权进程监听 Kubernetes Endpoints，然后将其值存储到 `ngx.shared.DICT` 中，工作进程通过查询 `ngx.shared.DICT` 来获取结果。

**Q: [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) 需要的权限有哪些？**

A: [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) 需要集群级 [ get,list,watch ] endpoints 和 endpointslices 资源的的权限，其声明式定义如下：

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

**Q: 怎样获取指定 [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) 的 Token 值？**

A: 假定你指定的 [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) 资源名为“kubernetes-discovery“, 命名空间为“apisix”, 请按如下步骤获取其 Token 值。

 1. 获取 _Secret_ 资源名。执行以下命令，输出的第一列内容就是目标 _Secret_ 资源名：

 ```shell
 kubectl -n apisix get secrets | grep kubernetes-discovery
 ```

 2. 获取 Token 值。假定你获取到的 _Secret_ 资源名为 "kubernetes-discovery-token-c64cv", 执行以下命令，输出内容就是目标 Token 值：

 ```shell
 kubectl -n apisix get secret kubernetes-discovery-token-c64cv -o jsonpath={.data.token} | base64 -d
 ```

## 调试 API

它还提供了用于调试的控制 api。

### 内存 Dump API

```shell
GET /v1/discovery/kubernetes/dump
```

例子

```shell
# curl http://127.0.0.1:9090/v1/discovery/kubernetes/dump | jq
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
