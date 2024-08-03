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

before() {
    # generating SSL certificates for Kafka
    sudo keytool -genkeypair -keyalg RSA -dname "CN=127.0.0.1" -alias 127.0.0.1 -keystore ./ci/pod/kafka/kafka-server/selfsigned.jks -validity 365 -keysize 2048 -storepass changeit
}

after() {
    docker exec -i apache-apisix-kafka-server1-1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 1 --topic test2
    docker exec -i apache-apisix-kafka-server1-1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 3 --topic test3
    docker exec -i apache-apisix-kafka-server2-1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server2:2181 --replication-factor 1 --partitions 1 --topic test4
    docker exec -i apache-apisix-kafka-server1-1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 1 --topic test-consumer
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
