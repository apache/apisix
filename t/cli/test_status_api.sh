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

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)

sleep 2

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

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
