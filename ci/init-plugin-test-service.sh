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

# A broker that is not registered in ZooKeeper yet rejects topic creation with
# "Replication factor: 1 larger than available brokers: 0". The failure used to be
# silent, and the topic was then auto-created with the default single partition on
# first produce, which quietly broke tests that expect a specific partition layout.
create_kafka_topic() {
    local container="$1"
    local zookeeper="$2"
    local partitions="$3"
    local topic="$4"

    for _ in $(seq 30); do
        if docker exec -i "$container" /opt/bitnami/kafka/bin/kafka-topics.sh --create \
            --zookeeper "$zookeeper" --replication-factor 1 \
            --partitions "$partitions" --topic "$topic"; then
            return 0
        fi
        sleep 2
    done

    echo "failed to create kafka topic $topic on $container"
    exit 1
}

after() {
    create_kafka_topic apache-apisix-kafka-server1-1 zookeeper-server1:2181 1 test2
    create_kafka_topic apache-apisix-kafka-server1-1 zookeeper-server1:2181 3 test3
    create_kafka_topic apache-apisix-kafka-server2-1 zookeeper-server2:2181 1 test4
    create_kafka_topic apache-apisix-kafka-server3-scram-1 zookeeper-server3:2181 1 test-scram-256
    create_kafka_topic apache-apisix-kafka-server3-scram-1 zookeeper-server3:2181 1 test-scram-512
    # Create user with SCRAM-SHA-512
    docker exec apache-apisix-kafka-server3-scram-1 /opt/bitnami/kafka/bin/kafka-configs.sh \
        --zookeeper zookeeper-server3:2181 \
        --alter \
        --add-config 'SCRAM-SHA-256=[password=admin-secret],SCRAM-SHA-512=[password=admin-secret]' \
        --entity-type users \
        --entity-name admin
    # prepare openwhisk env
    docker pull openwhisk/action-nodejs-v14:1.20.0
    docker run --rm -d --name openwhisk -p 3233:3233 -p 3232:3232 -v /var/run/docker.sock:/var/run/docker.sock openwhisk/standalone:1.0.0
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
    for i in $(seq 1 60); do
        if curl -sf localhost:8080 >/dev/null 2>&1; then
            break
        fi
        if [ "$i" -eq 60 ]; then
            echo "ERROR: keycloak (apisix_keycloak_new) failed to become ready"
            docker logs apisix_keycloak_new 2>&1 || true
            exit 1
        fi
        sleep 3
    done

    # install jq
    wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O jq
    chmod +x jq
    docker cp jq apisix_keycloak:/usr/bin/

    # configure keycloak
    docker exec apisix_keycloak bash /tmp/kcadm_configure_cas.sh
    docker exec apisix_keycloak bash /tmp/kcadm_configure_university.sh
    docker exec apisix_keycloak bash /tmp/kcadm_configure_basic.sh

    # wait for saml keycloak ready and configure it
    for i in $(seq 1 60); do
        if curl -sf localhost:8087 >/dev/null 2>&1; then
            break
        fi
        if [ "$i" -eq 60 ]; then
            echo "ERROR: keycloak (apisix_keycloak_saml) failed to become ready"
            docker logs apisix_keycloak_saml 2>&1 || true
            exit 1
        fi
        sleep 3
    done
    docker cp jq apisix_keycloak_saml:/usr/bin/
    docker exec apisix_keycloak_saml bash /tmp/kcadm_configure_saml.sh

    # configure clickhouse
    echo 'CREATE TABLE default.test (`host` String, `client_ip` String, `route_id` String, `service_id` String, `@timestamp` String, PRIMARY KEY(`@timestamp`)) ENGINE = MergeTree()' | curl 'http://localhost:8123/' --data-binary @-
    echo 'CREATE TABLE default.test (`host` String, `client_ip` String, `route_id` String, `service_id` String, `@timestamp` String, PRIMARY KEY(`@timestamp`)) ENGINE = MergeTree()' | curl 'http://localhost:8124/' --data-binary @-
}

before() {
    # download keycloak cas provider
    sudo wget -q https://github.com/jacekkow/keycloak-protocol-cas/releases/download/18.0.2/keycloak-protocol-cas-18.0.2.jar -O /opt/keycloak-protocol-cas-18.0.2.jar
}

case $1 in
    'after')
        after
        ;;
    'before')
        before
        ;;
esac
