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

docker run --rm -itd -p 6379:6379 --name apisix_redis redis:3.0-alpine
docker run --rm -itd -e HTTP_PORT=8888 -e HTTPS_PORT=9999 -p 8888:8888 -p 9999:9999 mendhak/http-https-echo
# Runs Keycloak version 10.0.2 with inbuilt policies for unit tests
docker run --rm -itd -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=123456 -p 8090:8080 -p 8443:8443 sshniro/keycloak-apisix:1.0.0
# spin up kafka cluster for tests (1 zookeper and 1 kafka instance)
docker network create kafka-net --driver bridge
docker run --name zookeeper-server -d -p 2181:2181 --network kafka-net -e ALLOW_ANONYMOUS_LOGIN=yes bitnami/zookeeper:3.6.0
docker run --name kafka-server1 -d --network kafka-net -e ALLOW_PLAINTEXT_LISTENER=yes -e KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper-server:2181 -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:9092 -p 9092:9092 -e KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true bitnami/kafka:latest
docker run --name eureka -d -p 8761:8761 --env ENVIRONMENT=apisix --env spring.application.name=apisix-eureka --env server.port=8761 --env eureka.instance.ip-address=127.0.0.1 --env eureka.client.registerWithEureka=true --env eureka.client.fetchRegistry=false --env eureka.client.serviceUrl.defaultZone=http://127.0.0.1:8761/eureka/ bitinit/eureka
sleep 5
docker exec -i kafka-server1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server:2181 --replication-factor 1 --partitions 1 --topic test2
docker exec -i kafka-server1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server:2181 --replication-factor 1 --partitions 3 --topic test3

# start skywalking
docker run --rm --name skywalking -d -p 1234:1234 -p 11800:11800 -p 12800:12800 apache/skywalking-oap-server:8.3.0-es6
# start consul servers
docker run --rm --name consul_1 -d -p 8500:8500 consul:1.7 consul agent -server -bootstrap-expect=1 -client 0.0.0.0 -log-level info -data-dir=/consul/data
docker run --rm --name consul_2 -d -p 8600:8500 consul:1.7 consul agent -server -bootstrap-expect=1 -client 0.0.0.0 -log-level info -data-dir=/consul/data

# start nacos server
docker network rm nacos_net
docker network create nacos_net
# nacos no auth server - for test no auth
docker run --rm -d --name nacos_no_auth --network nacos_net --hostname nacos2 --env NACOS_SERVERS="nacos1:8848 nacos2:8848" --env PREFER_HOST_MODE=hostname --env MODE=cluster --env EMBEDDED_STORAGE=embedded  --env JVM_XMS=512m --env JVM_XMX=512m --env JVM_XMN=256m -p8858:8848 nacos/nacos-server:1.4.1
# nacos auth server - for test auth
docker run --rm -d --name nacos_auth --network nacos_net --hostname nacos1 --env NACOS_AUTH_ENABLE=true --env NACOS_SERVERS="nacos1:8848 nacos2:8848" --env PREFER_HOST_MODE=hostname --env MODE=cluster --env EMBEDDED_STORAGE=embedded  --env JVM_XMS=512m --env JVM_XMX=512m --env JVM_XMN=256m -p8848:8848 nacos/nacos-server:1.4.1
url="127.0.0.1:8858/nacos/v1/ns/service/list?pageNo=1&pageSize=2"
until  [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $url)"  == "200" ]]; do
    echo 'wait nacos server...'
    sleep 1;
done
# register nacos service
rm -rf tmp
mkdir tmp
cd tmp
wget https://raw.githubusercontent.com/api7/nacos-test-service/main/spring-nacos-1.0-SNAPSHOT.jar
curl https://raw.githubusercontent.com/api7/nacos-test-service/main/Dockerfile | docker build -t nacos-test-service:1.0-SNAPSHOT -f - .
docker run -d --rm --network nacos_net --env SERVICE_NAME=APISIX-NACOS --env NACOS_ADDR=nacos2:8848 --env SUFFIX_NUM=1 -p 18001:18001 --name nacos-service1 nacos-test-service:1.0-SNAPSHOT
docker run -d --rm --network nacos_net --env SERVICE_NAME=APISIX-NACOS --env NACOS_ADDR=nacos2:8848 --env SUFFIX_NUM=2 -p 18002:18001 --name nacos-service2 nacos-test-service:1.0-SNAPSHOT
url="127.0.0.1:18002/hello"
until  [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $url)"  == "200" ]]; do
    echo 'wait nacos service...'
    sleep 1;
done
until  [[ $(curl -s "127.0.0.1:8858/nacos/v1/ns/service/list?pageNo=1&pageSize=2" | grep "APISIX-NACOS") ]]; do
    echo 'wait nacos reg...'
    sleep 1;
done
cd ..
