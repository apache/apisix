#!/usr/bin/env bash
# Quick check: Kafka 4.x at 127.0.0.1:39092 + topic test-kafka4 (for kafka-logger TEST 27/28)
# Usage: ./ci/check-kafka4-local.sh   (podman) or with CONTAINER_CMD=docker

set -e
CONTAINER_CMD="${CONTAINER_CMD:-podman}"
CONTAINER_NAME="${CONTAINER_NAME:-kafka-server4-kafka4}"
TOPIC="test-kafka4"
BOOTSTRAP="localhost:9092"

echo "=== 1. Container status ==="
$CONTAINER_CMD ps -a --filter name=$CONTAINER_NAME --format '{{.Names}} {{.Status}} {{.Ports}}'

echo ""
echo "=== 2. Create topic $TOPIC (idempotent) ==="
# Single-listener compose (advertised localhost:39092) may hang from inside; use TIMEOUT_CMD if set (e.g. gtimeout 10s).
${TIMEOUT_CMD:+$TIMEOUT_CMD }$CONTAINER_CMD exec -i $CONTAINER_NAME /opt/kafka/bin/kafka-topics.sh \
  --create --topic $TOPIC --bootstrap-server localhost:9092 \
  --partitions 1 --replication-factor 1 2>&1 || true

echo ""
echo "=== 3. List topics ==="
${TIMEOUT_CMD:+$TIMEOUT_CMD }$CONTAINER_CMD exec -i $CONTAINER_NAME /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>&1 || true

echo ""
echo "=== 4. Describe topic $TOPIC ==="
${TIMEOUT_CMD:+$TIMEOUT_CMD }$CONTAINER_CMD exec -i $CONTAINER_NAME /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic $TOPIC 2>&1 || true

echo ""
echo "Done. Run tests with: unset CI && prove -Itest-nginx/lib -I./ -r t/plugin/kafka-logger.t"
