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

# wait for keycloak ready
bash -c 'while true; do curl -s localhost:8080 &>/dev/null; ret=$?; [[ $ret -eq 0 ]] && break; sleep 3; done'
docker cp ci/kcadm_configure_cas.sh apisix_keycloak_new:/tmp/
docker exec apisix_keycloak_new bash /tmp/kcadm_configure_cas.sh
