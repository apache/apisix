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

## Summary

The kubernetes service discovery plugin list&watch real-time changes of kubernetes cluster v1.endpoints, \
then store its value into ngx.shared.kubernetes.\
Discovery plugin also provides a query interface in accordance with the _APISIX Discovery specification_

## Configuration

A detailed configuration for the kubernetes service discovery plugin is as follows:

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

      # only save endpoints with namespace not match one of [default, ^my-[a-z]+$ ]
      #not_match:
       #- default
       #- ^my-[a-z]+$

    # kubernetes discovery plugin support use label_selector
    # for the expression of label_selector, please refer to https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
    label_selector: |-
      first="a",second="b"
```

If the kubernetes service discovery plugin runs inside a pod, you can use minimal configuration:

```yaml
discovery:
  kubernetes: { }
```

If the kubernetes service discovery plugin runs outside a pod, you need to create or select a specified _ServiceAccount_,
get its token value, then use following configuration:

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

## Interface

the kubernetes service discovery plugin provides a query interface in accordance with the _APISIX Discovery specification_

**function:** \
 nodes(service_name)

**description:** \
  nodes() function attempts to look up the ngx.shared.kubernetes for nodes corresponding to service_name, \
  service_name should match pattern: _[namespace]/[name]:[portName]_

  + namespace: The namespace where the kubernetes endpoint is located

  + name: The name of the kubernetes endpoint

  + portName: The portName of the kubernetes endpoint, if there is no portName, use targetPort, port instead

**return value:** \
  if the kubernetes endpoint value is as follows:

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

  a nodes("default/plat-dev:3306") call will get follow result:

  ```
   {
       {
           host="10.5.10.109",
           port= 3306,
           weight= 100,
       },
       {
           host="10.5.10.110",
           port= 3306,
           weight= 100,
       },
   }
  ```

## Q&A

> Q: Why only support configuration token to access _Kubernetes ApiServer_ \
> A: Usually, we will use three ways to complete the authentication of _Kubernetes ApiServer_:
>
>+ mTLS
>+ token
>+ basic authentication
>
> Because lua-resty-http does not currently support mTLS, and basic authentication is not recommended,\
> So currently only the token authentication method is implemented

-------

> Q: APISIX inherits Nginx's multiple process model, does it mean that each nginx worker process will list&watch kubernetes v1.endpoints \
> A: Kubernetes service discovery plugin only uses privileged processes to listen&watch kubernetes v1.endpoints, then store the result\
> in ngx.shared.kubernetes, worker processes get results by querying ngx.shared.kubernetes
