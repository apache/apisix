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

before() {
    # generating SSL certificates for Kafka
    sudo keytool -genkeypair -keyalg RSA -dname "CN=127.0.0.1" -alias 127.0.0.1 -keystore ./ci/pod/kafka/kafka-server/selfsigned.jks -validity 365 -keysize 2048 -storepass changeit
}

after() {
    create_kafka_topic apache-apisix-kafka-server1-1 zookeeper-server1:2181 1 test2
    create_kafka_topic apache-apisix-kafka-server1-1 zookeeper-server1:2181 3 test3
    create_kafka_topic apache-apisix-kafka-server2-1 zookeeper-server2:2181 1 test4
    create_kafka_topic apache-apisix-kafka-server1-1 zookeeper-server1:2181 1 test-consumer
    # create messages for test-consumer
    for i in `seq 30`
    do
        docker exec -i apache-apisix-kafka-server1-1 bash -c "echo "testmsg$i" | /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server 127.0.0.1:9092 --topic test-consumer"
        echo "Produces messages to the test-consumer topic, msg: testmsg$i"
    done
    echo "Kafka service initialization completed"
}

case $1 in
    'after')
        after
        ;;
    'before')
        before
        ;;
esac
