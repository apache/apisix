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
### kubernetes

There are some yaml files for deploying apisix in Kubernetes.

### Prerequisites
- Install etcd

#### when using etcd-operator
when using etcd-operator, you need to change apisix-gw-config-cm.yaml:

* add CoreDNS IP into dns_resolver

```
dns_resolver:
  - 10.233.0.3      # default coreDNS cluster ip

```
* change etcd host

Following {your-namespace} should be changed to your namespace, for example `default`.
> Mention: must use `Full Qualified Domain Name`. Short name `etcd-cluster-client` is not work.

```
etcd:
  host:
    - "http://etcd-cluster-client.{your-namespace}.svc.cluster.local:2379"     # multiple etcd address
```

### Usage

#### Create configmap for apache incubator-apisix

```
$ kubectl apply -f apisix-gw-config-cm.yaml

or

$ kubectl create configmap apisix-gw-config.yaml --from-file=../conf/config.yaml
```

##### Note: you should modify etcd addr in config file `apisix-gw-config-cm.yaml` or `../conf/config.yaml` first

```
etcd:
  host:                           # it's possible to define multiple etcd hosts addresses of the same etcd cluster.
    - "http://127.0.0.1:2379"     # multiple etcd address
```

#### Create deployment for apache incubator-apisix

```
$ kubectl apply -f deployment.yaml
```

#### Create service for apache incubator-apisix

```
$ kubectl apply -f service.yaml
```

#### Create service for apache incubator-apisix (when using Aliyun SLB)

```
$ kubectl apply -f service-aliyun-slb.yaml
```

#### Scale apache incubator-apisix

```
$ kubectl scale deployment apisix-gw-deployment --replicas=4
```

#### Check running status

```
$ kubectl get cm | grep -i apisix
apisix-gw-config.yaml                             1      1d

$ kubectl get pod | grep -i apisix
apisix-gw-deployment-68df7c7578-5pvxb   1/1     Running   0          1d
apisix-gw-deployment-68df7c7578-kn89l   1/1     Running   0          1d
apisix-gw-deployment-68df7c7578-i830r   1/1     Running   0          1d
apisix-gw-deployment-68df7c7578-32ow1   1/1     Running   0          1d

$ kubectl get svc | grep -i apisix
apisix-gw-svc            LoadBalancer   172.19.33.28    10.253.0.11   80:31141/TCP,443:30931/TCP                  1d

```

#### Clean up (dangerous)

```
kubectl delete -f .
```
