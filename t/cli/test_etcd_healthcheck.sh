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

REGISTRY=gcr.io/etcd-development/etcd
ETCD_VERSION=v3.4.15
TOKEN=my-etcd-token
CLUSTER_STATE=new
NAME_1=etcd-node-0
NAME_2=etcd-node-1
NAME_3=etcd-node-2
PORT_1=32379
PORT_2=42379
PORT_3=52379
PORT_PEER_1=32380
PORT_PEER_2=42380
PORT_PEER_3=52380
CLUSTER=${NAME_1}=http://0.0.0.0:${PORT_PEER_1},${NAME_2}=http://0.0.0.0:${PORT_PEER_2},${NAME_3}=http://0.0.0.0:${PORT_PEER_3}
DATA_DIR=/var/lib/etcd

CreateEtcdNode() {
  docker run \
    -d \
    -p $2:$2 \
    -p $3:$3 \
    --volume=${DATA_DIR}:/etcd-data \
    --name $1 ${REGISTRY}:${ETCD_VERSION} \
    /usr/local/bin/etcd \
    --data-dir=/etcd-data --name $1 \
    --advertise-client-urls http://0.0.0.0:$2 --listen-client-urls http://0.0.0.0:$2 \
    --initial-cluster ${CLUSTER} \
    --initial-cluster-state ${CLUSTER_STATE} --initial-cluster-token ${TOKEN}
}

CreateEtcdNode ${NAME_1} ${PORT_1} ${PORT_PEER_1}
CreateEtcdNode ${NAME_2} ${PORT_2} ${PORT_PEER_2}
CreateEtcdNode ${NAME_3} ${PORT_3} ${PORT_PEER_3}



