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
# Entrypoint for test-runner container. Expects APISIX source mounted at /workspace.
# Waits for etcd (and optionally Kafka), then runs make deps, make init, prove.
#
set -e

export OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
export PATH="$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH"
export PERL5LIB="/workspace:/test-nginx/lib:$PERL5LIB"

cd /workspace
# Use a servroot under /tmp so bind-mounted workspace is not used (avoids permission issues with sockets)
export TEST_NGINX_SERVROOT="${TEST_NGINX_SERVROOT:-/tmp/apisix-servroot}"
rm -rf "$TEST_NGINX_SERVROOT" 2>/dev/null || true

# Wait for etcd
ETCD_HOST="${ETCD_HOST:-127.0.0.1}"
# Override etcd host for init_etcd (APISIX reads APISIX_DEPLOYMENT_ETCD_HOST as JSON array)
export APISIX_DEPLOYMENT_ETCD_HOST="[\"http://${ETCD_HOST}:2379\"]"
# So test cleanup (etcdctl del, init_etcd) and APISIX.pm config use the same etcd
export ETCDCTL_ENDPOINTS="http://${ETCD_HOST}:2379"
echo "Waiting for etcd at $ETCD_HOST:2379 ..."
for i in $(seq 1 60); do
    if curl -s --connect-timeout 2 "http://$ETCD_HOST:2379/version" >/dev/null 2>&1; then
        echo "etcd is ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "etcd did not become ready in time."
        exit 1
    fi
    sleep 1
done

# Optional: wait for Kafka 4 (when KAFKA4_BROKER_HOST is set, e.g. in bridge network)
if [ -n "${KAFKA4_BROKER_HOST}" ]; then
    KAFKA_PORT="${KAFKA4_BROKER_PORT:-19092}"
    echo "Waiting for Kafka 4 at $KAFKA4_BROKER_HOST:$KAFKA_PORT ..."
    for i in $(seq 1 60); do
        if (echo >/dev/tcp/"$KAFKA4_BROKER_HOST"/"$KAFKA_PORT") 2>/dev/null; then
            echo "Kafka is reachable."
            break
        fi
        [ "$i" -eq 60 ] && echo "Kafka did not become reachable in time (continuing anyway)."
        sleep 1
    done
fi

make utils
make deps
make init

TEST_FILES="${TEST_FILES:-t/plugin/kafka-logger.t}"
echo "Running: prove -Itest-nginx/lib -I./ $TEST_FILES"
FLUSH_ETCD=1 prove --timer -I/test-nginx/lib -I/workspace $TEST_FILES
