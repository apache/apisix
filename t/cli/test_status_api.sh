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

git checkout conf/config.yaml


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
    prefix: /apisix
nginx_config:
  error_log_level: info
apisix:
  status:
    ip: 127.0.0.1
    port: 7085
' > conf/config.yaml

# create 3 node etcd cluster in docker
ETCD_NAME_0=etcd0
ETCD_NAME_1=etcd1
ETCD_NAME_2=etcd2
docker compose -f ./t/cli/docker-compose-etcd-cluster.yaml up -d

make run

sleep 0.5

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)

sleep 2

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

# The status server listens with enable_process=privileged_agent. On a buggy
# runtime the privileged agent closes an already-closed listen fd during startup
# and logs "[emerg] ... Bad file descriptor" (apisix-nginx-module#116). A clean
# start must not contain it.
if grep -q "Bad file descriptor" logs/error.log; then
    echo "failed: privileged agent hit EBADF on a listen fd (apisix-nginx-module#116)"
    exit 1
fi
echo "passed: no 'Bad file descriptor' from the privileged agent listener"

# stop two etcd endpoints but status api should return 200 as all workers are synced
docker stop ${ETCD_NAME_0}
docker stop ${ETCD_NAME_1}

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

docker stop ${ETCD_NAME_2}

echo "/status/ready returns 200 even when etcd endpoints are down as all workers are synced"
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

docker compose -f ./t/cli/docker-compose-etcd-cluster.yaml down
