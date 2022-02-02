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

Kubernetes 服务发现插件以 ListWatch 方式监听 Kubernetes 集群的 的 v1.endpoints 的实时变化,
并将其值存储在 ngx.shared.DICT 中, 同时遵循 APISix Discovery 规范提供对外查询接口

# Kubernetes 服务发现插件的配置

Kubernetes 服务发现的样例配置如下:

```yaml
discovery:
  kubernetes:
    service:
      # kubernetes apiserver schema, options [ http | https ]
      schema: https #default https

      # kubernetes apiserver host, options [ ipv4 | ipv6 | domain | env variable]
      host: 10.0.8.95 #default ${KUBERNETES_SERVICE_HOST}

      # kubernetes apiserver port, you can enter port number or environment variable
      port: 6443  #default ${KUBERNETES_SERVICE_PORT}

    client:
      # kubernetes serviceaccount token or token_file
      token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token"
      #token:

    # kubernetes discovery plugin support use namespace_selector
    # you can use one of [ equal | not_equal | match | not_match ] filter namespace
    namespace_selector:
      equal: default
      #not_equal:
      #match:
      #not_match:

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
      host: # Enter ApiServer Host Value Here
      port: # Enter ApiServer Port Value Here
      schema: https
    client:
      token: # Enter ServiceAccount Token Value Here
      #token_file: # Enter File Path Here
```

# Kubernetes 服务发现插件的使用

Kubernetes 服务发现插件提供与其他服务发现插件相同的查询接口 -> nodes(service_name) \
service_name 的 pattern 如下:
> _[namespace]/[name]:[portName]_

如果 kubernetes Endpoint 没有定义 portName, Kubernetes 服务发现插件会依次使用 targetPort, port 代替

# Q&A

> Q: 为什么只支持配置 token 来访问 kubernetes apiserver \
> A: 通常情况下,我们会使用三种方式与 kubernetes apiserver 通信 :
>
>+ mTLS
>+ token
>+ basic authentication
>
> 因为 lua-resty-http 目前不支持 mTLS ,以及 basic authentication 不被推荐使用,\
> 所以当前只实现了 token 认证方式

-------

> Q: APISix 是多进程模型, 是否意味着每个 APISix 业务进程都会去监听 kubernetes apiserver \
> A: Kubernetes 服务发现插件只使用特权进程监听 kubernetes 集群,然后将结果存储在 ngx.shared.DICT中, \
> 业务进程是通过查询 ngx.shared.DICT 获取结果的
