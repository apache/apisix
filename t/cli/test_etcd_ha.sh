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

make init && make run

if [ "$?" != 0 ]; then
    echo "FAIL: stop only one etcd node APISIX should start normally"
    exit 1
fi

echo "OK: APISIX successfully to start, stop only one etcd node"

make stop

# case 2: stop two etcd nodes (result: start failure)
docker stop ${ETCD_NAME_1}

make init && make run

if [ "$?" == 0 ]; then
    echo "FAIL: etcd has stopped two nodes, APISIX should fail to start"
    exit 1
fi

echo "OK: APISIX failed to start, etcd cluster must have two or more healthy nodes"


# case 3: stop all etcd nodes (result: start failure)
docker stop ${ETCD_NAME_2}

make init && make run

if [ "$?" == 0 ]; then
    echo "FAIL: all etcd nodes have stopped, APISIX should not be able to start"
    exit 1
fi

echo "OK: APISIX failed to start, all etcd nodes have stopped"

# stop etcd docker container
docker-compose down
