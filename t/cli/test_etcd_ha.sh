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

ETCD_NAME_0=etcd0
ETCD_NAME_1=etcd1
ETCD_NAME_2=etcd2

echo '
etcd:
  host:
    - "http://127.0.0.1:23790"
    - "http://127.0.0.1:23791"
    - "http://127.0.0.1:23792"
' > conf/config.yaml

docker-compose -f ./t/cli/docker-compose-etcd-cluster.yaml up -d

# case 1: stop one etcd nodes (result: start successful)
docker stop ${ETCD_NAME_0}

out=$(make init 2>&1)
if echo "$out" | grep "23790" | grep "connection refused"; then
    echo "passed: APISIX successfully to start, stop only one etcd node"
else
    echo "failed: stop only one etcd node APISIX should start normally"
    exit 1
fi

# case 2: stop two etcd nodes (result: start failure)
docker stop ${ETCD_NAME_1}

out=$(make init 2>&1)
if echo "$out" | grep "etcd cluster must have two or more healthy nodes"; then
    echo "passed: APISIX failed to start, etcd cluster must have two or more healthy nodes"
else
    echo "failed: etcd has stopped two nodes, APISIX should fail to start"
    exit 1
fi

# case 3: stop all etcd nodes (result: start failure)
docker stop ${ETCD_NAME_2}

out=$(make init 2>&1)
if echo "$out" | grep "all etcd nodes are unavailable"; then
    echo "passed: APISIX failed to start, all etcd nodes have stopped"
else
    echo "failed: all etcd nodes have stopped, APISIX should not be able to start"
    exit 1
fi

# stop etcd docker container
docker-compose down
