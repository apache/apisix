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

Kubernetes 服务发现插件以 ListWatch 方式监听 Kubernetes 集群的 的 endpoints/v1 资源的实时变化, 并将其值存储在 shared.DICT 中,
以及提供对外查询接口

# Kubernetes 服务发现插件的配置

Kubernetes 服务发现的样例配置如下:

```yaml
discovery:
  kubernetes:
    service:
      #kubernetes apiserver schema , option [ http | https ], default https
      schema: https

      # kubernetes apiserver host, you can set ipv4,ipv6 ,domain or environment variable
      # default ${KUBERNETES_SERVICE_HOST}
      host: 10.0.8.95

      # kubernetes apiserver port, you can set number or environment variable
      # default ${KUBERNETES_SERVICE_PORT}      
      port: 6443

    client:
      # kubernetes serviceaccount token or token_file
      # default setup token_file and value is "/var/run/secrets/kubernetes.io/serviceaccount/token"
      #token: 
      token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token"

    # kubernetes discovery plugin support watch endpoints in specific namespace 
    # you can use [ equal | not_equal | match | not_match ] to filter your specified namespace
    # [ match | not_match ] support regular expression (using ngx.re.match )
    namespace_selector:
      equal: default
#      not_equal:
#      match:
#      not_match:
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
      host: [ ApiServer Host Value Here ]
      port: [ ApiServer Port Value Here ]
      schema: https
    client:
      token: [ ServiceAccount Token Value Here ]
```

# Kubernetes 服务发现插件的使用

Kubernetes 服务发现插件提供与其他服务发现相同的查询接口 -> nodes(service_name)

其中 service_name 的 pattern 如下:
> _[namespace]/[name]:[portName]_

某些 endpoints 可能没有定义 portName, Kubernetes 服务发现插件会依次使用 targetPort, port 代替

# Q&A

> Q: 为什么只支持配置 token 来访问 kubernetes apiserver ,可以使用 kubernetes config 吗

> A: 通常情况下,我们会使用三种方式与 kubernetes Apiserver 通信 :
>  + mTLS
>  + token
>  + basic authentication \
> 但因为 apisix.http 目前并没有支持 mTLS ,以及 basic authentication 并不被推荐使用,\
> 所以只实现了 token 的方式, 这也意味着不支持 kubernetes config
-------
> Q: APISix 是多进程模型, 是否意味着每个 APISix 业务进程都会去 监听 kubernetes apiserver

> A: Kubernetes 服务发现插件只使用特权进程监听 kubernetes 集群,然后将获取到结果存储在 ngx.shared.DICT中 业务进程是通过查询 ngx.shared.DICT 获取结果的

------

