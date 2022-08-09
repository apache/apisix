#!/usr/bin/env bash
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

docker exec -i apache-apisix_kafka-server1_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 1 --topic test2
docker exec -i apache-apisix_kafka-server1_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 3 --topic test3
docker exec -i apache-apisix_kafka-server2_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server2:2181 --replication-factor 1 --partitions 1 --topic test4

# prepare openwhisk env
docker pull openwhisk/action-nodejs-v14:nightly
docker run --rm -d --name openwhisk -p 3233:3233 -p 3232:3232 -v /var/run/docker.sock:/var/run/docker.sock openwhisk/standalone:nightly
docker exec -i openwhisk waitready
docker exec -i openwhisk bash -c "wsk package create pkg"
docker exec -i openwhisk bash -c "wsk action update /guest/pkg/testpkg <(echo 'function main(args){return {\"hello\": \"world\"}}') --kind nodejs:14"
docker exec -i openwhisk bash -c "wsk action update test <(echo 'function main(args){return {\"hello\": \"test\"}}') --kind nodejs:14"
docker exec -i openwhisk bash -c "wsk action update test-params <(echo 'function main(args){return {\"hello\": args.name || \"test\"}}') --kind nodejs:14"
docker exec -i openwhisk bash -c "wsk action update test-statuscode <(echo 'function main(args){return {\"statusCode\": 407}}') --kind nodejs:14"
docker exec -i openwhisk bash -c "wsk action update test-headers <(echo 'function main(args){return {\"headers\": {\"test\":\"header\"}}}') --kind nodejs:14"
docker exec -i openwhisk bash -c "wsk action update test-body <(echo 'function main(args){return {\"body\": {\"test\":\"body\"}}}') --kind nodejs:14"


docker exec -i rmqnamesrv rm /home/rocketmq/rocketmq-4.6.0/conf/tools.yml
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test2 -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test3 -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test4 -c DefaultCluster

# prepare vault kv engine
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"

# prepare openfunction env
prepare_kind_k8s() {
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
    chmod +x ./kind
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kind create cluster --name myk8s-01
}

install_openfuncntion() {
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    helm repo add openfunction https://openfunction.github.io/charts/
    helm repo update
    kubectl create namespace openfunction
    helm install openfunction --set global.Keda.enabled=false --set global.Dapr.enabled=false openfunction/openfunction -n openfunction
    kubectl wait pods --all  --for=condition=Ready --timeout=300s -n openfunction
    kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
    kubectl delete deployment -n keda --all
    kubectl delete deployment -n dapr-system --all
    kubectl delete pod -n keda --all
    kubectl delete pod -n dapr-system --all
}

set_container_registry_secret() {
    REGISTRY_SERVER=https://index.docker.io/v1/ REGISTRY_USER=apisixtestaccount123 REGISTRY_PASSWORD=apisixtestaccount
    kubectl create secret docker-registry push-secret \
        --docker-server=$REGISTRY_SERVER \
        --docker-username=$REGISTRY_USER \
        --docker-password=$REGISTRY_PASSWORD
}

create_functions() {
    wget https://raw.githubusercontent.com/jackkkkklee/samples/release-0.6/functions/knative/hello-world-go/function-sample.yaml
    wget https://raw.githubusercontent.com/jackkkkklee/samples/main/functions/knative/hello-world-go/function-sample-test-body.yaml

    kubectl apply -f function-sample.yaml
    kubectl apply -f function-sample-test-body.yaml

    kubectl set resources deployment -n openfunction --all=true --requests=cpu=40m,memory=64Mi
    kubectl set resources deployment -n kube-system --all=true --requests=cpu=50m,memory=64Mi

    kubectl wait fn function-sample --for=jsonpath='{.status.build.state}'=Succeeded  --timeout=500s
    kubectl wait fn function-sample --for=jsonpath='{.status.build.state}'=Running  --timeout=500s
    kubectl wait fn test-body --for=jsonpath='{.status.build.state}'=Succeeded  --timeout=500s
    kubectl wait fn test-body --for=jsonpath='{.status.build.state}'=Running  --timeout=500s

}

set_ingress_controller() {
    htpasswd -cb auth test test
    kubectl create secret generic basic-auth --from-file=auth

    kubectl patch ingress openfunction -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/auth-type":"basic","nginx.ingress.kubernetes.io/auth-secret":"basic-auth","nginx.ingress.kubernetes.io/auth-realm":"Authentication Required - test"}}}'
    kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $'spec:\n type: NodePort'
    kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"ports":[{"appProtocol":"http","name":"myhttp","nodePort": 30585,"port":  80,"protocol": "TCP", "targetPort": "http"}]}}'
  }
port_forward() {
    nohup kubectl port-forward --address 0.0.0.0  --namespace=ingress-nginx service/ingress-nginx-controller 30585:80 >/dev/null 2>&1 &
}

prepare_kind_k8s
install_openfuncntion
set_container_registry_secret
create_functions
set_ingress_controller
port_forward
