### Usage

#### Create configmap for apache incubator-apisix

```
$ kubectl apply -f apisix-gw-config-cm.yaml
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

#### Clean up

```
kubectl delete -f .
```
