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

# 基于 Kubernetes 的服务发现

Kubernetes 服务发现插件以 ListWatch 方式监听 Kubernetes 集群 v1.endpoints 的实时变化,
并将其值存储在 ngx.shared.dict 中, 同时遵循 APISIX Discovery 规范提供查询接口

# Kubernetes 服务发现插件的配置

Kubernetes 服务发现插件的样例配置如下:

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

如果 Kubernetes 服务插件运行在 Pod 内, 你可以使用最简配置:

```yaml
discovery:
  kubernetes: { }
```

如果 Kubernetes 服务插件运行在 Pod 外, 你需要新建或选取指定的 ServiceAccount, 获取其 Token 值, 并使用如下配置:

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

# Kubernetes 服务发现插件的使用

Kubernetes 服务发现插件提供与其他服务发现插件相同的查询接口 -> nodes(service_name) \
service_name 的 pattern 如下:
> _[namespace]/[name]:[portName]_

如果 kubernetes Endpoint 没有定义 portName, Kubernetes 服务发现插件会依次使用 targetPort, port 代替

# Q&A

> Q: 为什么只支持配置 token 来访问 Kubernetes ApiServer \
> A: 通常情况下,我们会使用三种方式与 Kubernetes ApiServer 通信 :
>
>+ mTLS
>+ token
>+ basic authentication
>
> 因为 lua-resty-http 目前不支持 mTLS, 以及 basic authentication 不被推荐使用,\
> 所以当前只实现了 token 认证方式

-------

> Q: APISIX 是多进程模型, 是否意味着每个 APISIX 工作进程都会监听 Kubernetes v1.endpoints \
> A: Kubernetes 服务发现插件只使用特权进程监听 Kubernetes v1.endpoints, 然后将结果存储\
> 在 ngx.shared.dict 中, 业务进程是通过查询 ngx.shared.dict 来获取结果的
