---
title: Kubernetes
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

Kubernetes 服务发现模块以 [_List-Watch_](https://kubernetes.io/docs/reference/using-api/api-concepts) 方式监听 [_Kubernetes_](https://kubernetes.io) 集群 [_Endpoints_](https://kubernetes.io/docs/concepts/services-networking/service) 资源的实时变化，
并将其值存储到 ngx.shared.kubernetes 中 \
模块同时遵循 [_APISIX Discovery 规范_](https://github.com/apache/apisix/blob/master/docs/zh/latest/discovery.md) 提供了节点查询接口

## Kubernetes 服务发现模块的配置

Kubernetes 服务发现模块的完整配置如下：

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

    # kubernetes discovery plugin support use namespace_selector
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

    # kubernetes discovery plugin support use label_selector
    # for the expression of label_selector, please refer to https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
    label_selector: |-
      first="a",second="b"
```

如果 Kubernetes 服务发现模块运行在 Pod 内，你可以使用最简配置：

```yaml
discovery:
  kubernetes: { }
```

如果 Kubernetes 服务发现模块运行在 Pod 外，你需要新建或选取指定的 [_ServiceAccount_](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/), 获取其 Token 值，然后使用如下配置：

```yaml
discovery:
  kubernetes:
    service:
      schema: https
      host: # enter apiserver host value here
      port: # enter apiServer port value here
    client:
      token: # enter serviceaccount token value here
      #token_file: # enter file path here
```

## Kubernetes 服务发现模块的查询接口

Kubernetes 服务发现模块遵循 [_APISIX Discovery 规范_](https://github.com/apache/apisix/blob/master/docs/zh/latest/discovery.md) 提供查询接口

**函数：**
nodes(service_name)

**说明：**
service_name 必须满足格式: [namespace]/[name]:[portName]

+ namespace: Endpoints 所在的命名空间

+ name: Endpoints 的资源名

+ portName: Endpoints 定义包含的 portName，如果 Endpoints 没有定义 portName，请使用 targetPort,Port 代替

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
  ```

nodes("default/plat-dev:3306") 调用会得到如下的返回值：

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

> Q: 为什么只支持配置 token 来访问 Kubernetes APIServer \
> A: 一般情况下，我们有三种方式可以完成与 Kubernetes APIServer 的认证：
>
>+ mTLS
>+ token
>+ basic authentication
>
> 因为 lua-resty-http 目前不支持 mTLS, basic authentication 不被推荐使用，\
> 所以当前只实现了 token 认证方式

---

> Q: APISIX 继承了 Nginx 的多进程模型，是否意味着每个 APISIX 工作进程都会监听 Kubernetes Endpoints \
> A: Kubernetes 服务发现模块只使用特权进程监听 Kubernetes Endpoints，然后将其值存储\
> 到 ngx.shared.kubernetes，工作进程通过查询 ngx.shared.kubernetes 来获取结果

---

> Q: 怎样获取指定 ServiceAccount 的 Token 值 \
> A: 假定你指定的 ServiceAccount 资源名为 “kubernetes-discovery“, 命名空间为 “apisix”, 请按如下步骤获取其 Token 值
>
> 1. 获取 _Secret_ 资源名: \
     > 执行以下命令，输出的第一列内容就是目标 _Secret_ 资源名
>
> ```shell
> kubectl -n apisix get secrets | grep kubernetes-discovery
> ```
>
> 2. 获取 Token 值: \
     > 假定你获取到的 _Secret_ 资源名为 "kubernetes-discovery-token-c64cv", 执行以下命令，输出内容就是目标 Token 值
>
> ```shell
> kubectl -n apisix get secret kubernetes-discovery-token-c64cv -o jsonpath={.data.token} | base64 -d
> ```
