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
# Run kafka-logger tests locally using a podman pod (shared network namespace).
# All containers share 127.0.0.1 so hardcoded addresses in tests work correctly.
# Usage: from repo root:  ci/pod/run-test-local.sh
#
set -e

COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$COMPOSE_DIR/../.." && pwd)"
cd "$REPO_ROOT"

POD_NAME=apisix-test-pod
RUNNER_IMAGE=pod-test-runner

cleanup() {
  echo "Cleaning up pod..."
  podman pod rm -f "$POD_NAME" 2>/dev/null || true
}

trap cleanup EXIT

# Remove any existing pod from a previous run
podman pod rm -f "$POD_NAME" 2>/dev/null || true

echo "Creating pod $POD_NAME..."
podman pod create --name "$POD_NAME"

# --- etcd ---
echo "Starting etcd..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-etcd" \
  -e ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379 \
  -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://127.0.0.1:2380 \
  -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380 \
  -e ETCD_INITIAL_CLUSTER=default=http://127.0.0.1:2380 \
  quay.io/coreos/etcd:v3.5.4

# --- Zookeeper (for kafka-server1 & kafka-server2) ---
echo "Starting Zookeeper..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-zookeeper" \
  -e ALLOW_ANONYMOUS_LOGIN=yes \
  bitnamilegacy/zookeeper:3.6.0

# --- kafka-server1: PLAINTEXT on 9092 (tests use 127.0.0.1:9092) ---
echo "Starting kafka-server1 (port 9092)..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-kafka1" \
  -e ALLOW_PLAINTEXT_LISTENER=yes \
  -e KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true \
  -e KAFKA_CFG_BROKER_ID=1 \
  -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:9092 \
  -e KAFKA_CFG_ZOOKEEPER_CONNECT=127.0.0.1:2181 \
  bitnamilegacy/kafka:2.8.1

# --- Zookeeper 2 (for kafka-server2, separate cluster like CI) ---
echo "Starting Zookeeper 2 (port 12181)..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-zookeeper2" \
  -e ALLOW_ANONYMOUS_LOGIN=yes \
  -e ZOO_PORT_NUMBER=12181 \
  -e JVMFLAGS="-Dzookeeper.admin.enableServer=false" \
  bitnamilegacy/zookeeper:3.6.0

# --- kafka-server2: PLAINTEXT 19092, SASL_PLAINTEXT 19094 (tests use 127.0.0.1:19094) ---
echo "Starting kafka-server2 (ports 19092/19094 SASL)..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-kafka2" \
  -e ALLOW_PLAINTEXT_LISTENER=yes \
  -e KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=false \
  -e KAFKA_CFG_BROKER_ID=1 \
  -e KAFKA_CFG_LISTENERS=PLAINTEXT://0.0.0.0:19092,SASL_PLAINTEXT://0.0.0.0:19094 \
  -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:19092,SASL_PLAINTEXT://127.0.0.1:19094 \
  -e KAFKA_CFG_ZOOKEEPER_CONNECT=127.0.0.1:12181 \
  -v "$REPO_ROOT/ci/pod/kafka/kafka-server/kafka_jaas.conf:/opt/bitnami/kafka/config/kafka_jaas.conf:ro" \
  bitnamilegacy/kafka:2.8.1

# --- Kafka 4 (KRaft mode, client on 39092) ---
echo "Starting Kafka 4 (port 39092)..."
podman run -d --pod "$POD_NAME" --name "${POD_NAME}-kafka4" \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=CLIENT://:39092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=CLIENT://127.0.0.1:39092 \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,CONTROLLER:PLAINTEXT \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e CLUSTER_ID=4L6g3nShT-eMCtK--X86sw \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  apache/kafka:4.0.0

# --- Wait for Zookeepers ---
echo "Waiting for Zookeeper 1..."
for i in $(seq 1 60); do
  if podman logs "${POD_NAME}-zookeeper" 2>&1 | grep -q "Started AdminServer"; then
    echo "Zookeeper 1 is ready."
    break
  fi
  [ "$i" -eq 60 ] && { echo "Zookeeper 1 did not become ready"; exit 1; }
  sleep 3
done
echo "Waiting for Zookeeper 2..."
for i in $(seq 1 60); do
  if podman logs "${POD_NAME}-zookeeper2" 2>&1 | grep -q "binding to port.*12181"; then
    echo "Zookeeper 2 is ready."
    break
  fi
  [ "$i" -eq 60 ] && { echo "Zookeeper 2 did not become ready"; exit 1; }
  sleep 3
done

# --- Wait for kafka-server1 and create topics ---
echo "Waiting for kafka-server1..."
for i in $(seq 1 60); do
  if podman exec "${POD_NAME}-kafka1" /opt/bitnami/kafka/bin/kafka-topics.sh \
    --bootstrap-server 127.0.0.1:9092 --list 2>/dev/null; then
    echo "kafka-server1 is ready."
    break
  fi
  [ "$i" -eq 60 ] && { echo "kafka-server1 did not become ready"; exit 1; }
  sleep 2
done

echo "Creating topics on kafka-server1 (test2, test3)..."
podman exec "${POD_NAME}-kafka1" /opt/bitnami/kafka/bin/kafka-topics.sh \
  --create --if-not-exists --zookeeper 127.0.0.1:2181 --replication-factor 1 --partitions 1 --topic test2
podman exec "${POD_NAME}-kafka1" /opt/bitnami/kafka/bin/kafka-topics.sh \
  --create --if-not-exists --zookeeper 127.0.0.1:2181 --replication-factor 1 --partitions 3 --topic test3

# --- Wait for kafka-server2 and create topics ---
echo "Waiting for kafka-server2..."
for i in $(seq 1 60); do
  if podman exec "${POD_NAME}-kafka2" bash -c "(echo >/dev/tcp/127.0.0.1/19092) 2>/dev/null"; then
    echo "kafka-server2 is ready."
    break
  fi
  [ "$i" -eq 60 ] && { echo "kafka-server2 did not become ready"; exit 1; }
  sleep 2
done
sleep 5

echo "Creating topic on kafka-server2 (test4)..."
podman exec "${POD_NAME}-kafka2" /opt/bitnami/kafka/bin/kafka-topics.sh \
  --create --if-not-exists --zookeeper 127.0.0.1:12181 --replication-factor 1 --partitions 1 --topic test4

# --- Wait for Kafka 4 and create topics ---
echo "Waiting for Kafka 4..."
sleep 10
for i in $(seq 1 30); do
  if podman exec "${POD_NAME}-kafka4" /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server 127.0.0.1:39092 --list 2>/dev/null; then
    echo "Kafka 4 is ready."
    break
  fi
  [ "$i" -eq 30 ] && { echo "Kafka 4 did not become ready"; exit 1; }
  sleep 2
done

echo "Creating topic on Kafka 4 (test-kafka4)..."
podman exec "${POD_NAME}-kafka4" /opt/kafka/bin/kafka-topics.sh \
  --create --if-not-exists --bootstrap-server 127.0.0.1:39092 \
  --topic test-kafka4 --replication-factor 1 --partitions 1

echo "All services ready, all topics created."

# --- Build test runner image ---
echo "Building test-runner image..."
podman build -q -f ci/docker/Dockerfile.test-runner -t "$RUNNER_IMAGE" .

# --- Run tests ---
# In a pod, all containers share 127.0.0.1
echo "Running kafka-logger tests..."
podman run --rm --pod "$POD_NAME" \
  -v "$REPO_ROOT:/workspace:rw" \
  -e ETCD_HOST=127.0.0.1 \
  -e KAFKA4_BROKER_HOST=127.0.0.1 \
  -e KAFKA4_BROKER_PORT=39092 \
  -e TEST_FILES=t/plugin/kafka-logger.t \
  "$RUNNER_IMAGE"

echo "Tests finished."
