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

. ./t/cli/common.sh

# create 3 node etcd cluster in docker
ETCD_NAME_0=etcd0
ETCD_NAME_1=etcd1
ETCD_NAME_2=etcd2
HEALTH_CHECK_RETRY_TIMEOUT=10

if [ -z "logs/error.log" ]; then
    git checkout logs/error.log
fi

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:23790"
      - "http://127.0.0.1:23791"
      - "http://127.0.0.1:23792"
  health_check_timeout: '"$HEALTH_CHECK_RETRY_TIMEOUT"'
  timeout: 2
' > conf/config.yaml

docker-compose -f ./t/cli/docker-compose-etcd-cluster.yaml up -d

# case 1: Check apisix not got effected when one etcd node disconnected
make init && make run

docker stop ${ETCD_NAME_0}
code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: apisix got effect when one etcd node out of a cluster disconnected"
    exit 1
fi
docker start ${ETCD_NAME_0}

docker stop ${ETCD_NAME_1}
code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: apisix got effect when one etcd node out of a cluster disconnected"
    exit 1
fi
docker start ${ETCD_NAME_1}

make stop

echo "passed: apisix not got effected when one etcd node disconnected"

# case 2: Check when all etcd nodes disconnected, apisix trying to reconnect with backoff, and could successfully recover when reconnected
make init && make run

docker stop ${ETCD_NAME_0} && docker stop ${ETCD_NAME_1} && docker stop ${ETCD_NAME_2}

sleep_till=$(date +%s -d "$DATE + $HEALTH_CHECK_RETRY_TIMEOUT second")

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ $code -eq 200 ]; then
    echo "failed: apisix not got effect when all etcd nodes disconnected"
    exit 1
fi

docker start ${ETCD_NAME_0} && docker start ${ETCD_NAME_1} && docker start ${ETCD_NAME_2}

# case 3: sleep till etcd health check try to check again
current_time=$(date +%s)
sleep_seconds=$(( $sleep_till - $current_time + 3))
if [ "$sleep_seconds" -gt 0 ]; then
    sleep $sleep_seconds
fi

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: apisix could not recover when etcd node recover"
    docker ps
    cat logs/error.log
    exit 1
fi

make stop

echo "passed: when all etcd nodes disconnected, apisix trying to reconnect with backoff, and could successfully recover when reconnected"

# case 4: stop one etcd node (result: start successful)
docker stop ${ETCD_NAME_0}

out=$(make init 2>&1)
if echo "$out" | grep "23790" | grep "connection refused"; then
    echo "passed: APISIX successfully to start, stop only one etcd node"
else
    echo "failed: stop only one etcd node APISIX should start normally"
    exit 1
fi

# case 5: stop two etcd nodes (result: start failure)
docker stop ${ETCD_NAME_1}

out=$(make init 2>&1 || true)
if echo "$out" | grep "23791" | grep "connection refused"; then
    echo "passed: APISIX failed to start, etcd cluster must have two or more healthy nodes"
else
    echo "failed: two etcd nodes have been stopped, APISIX should fail to start"
    exit 1
fi

# case 6: stop all etcd nodes (result: start failure)
docker stop ${ETCD_NAME_2}

out=$(make init 2>&1 || true)
if echo "$out" | grep "23792" | grep "connection refused"; then
    echo "passed: APISIX failed to start, all etcd nodes have stopped"
else
    echo "failed: all etcd nodes have stopped, APISIX should not be able to start"
    exit 1
fi

# stop etcd docker container
docker-compose -f ./t/cli/docker-compose-etcd-cluster.yaml down
