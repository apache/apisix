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

# clean etcd data
etcdctl del / --prefix

# data_plane does not write data to etcd
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - https://127.0.0.1:12379
        prefix: "/apisix"
        timeout: 30
        tls:
            verify: false
' > conf/config.yaml

make run

sleep 1

res=$(etcdctl get / --prefix | wc -l)

if [ ! $res -eq 0 ]; then
    echo "failed: data_plane should not write data to etcd"
    exit 1
fi

echo "passed: data_plane does not write data to etcd"

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes -H "X-API-KEY: $admin_key")
make stop

if [ ! $code -eq 404 ]; then
    echo "failed: data_plane should not enable Admin API"
    exit 1
fi

echo "passed: data_plane should not enable Admin API"

echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - https://127.0.0.1:12379
        prefix: "/apisix"
        timeout: 30
' > conf/config.yaml

out=$(make run 2>&1 || true)
make stop
if ! echo "$out" | grep 'failed to load the configuration: https://127.0.0.1:12379: certificate verify failed'; then
    echo "failed: should verify certificate by default"
    exit 1
fi

echo "passed: should verify certificate by default"


# echo '
# deployment:
#     role: data_plane
#     role_data_plane:
#         config_provider: etcd
#     etcd:
#         host:
#             - https://127.0.0.1:12379
#         prefix: "/apisix"
#         timeout: 30
# ' > conf/config.yaml


# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml up -d
# sleep 3
# output=$(./bin/apisix init 2>&1 || true)
# make stop
# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml down

# if ! echo "$output" | grep 'etcd is not allowed to be accessed anonymously when deployment role is data_plane'; then
#     echo "failed: etcd should not be accessed anonymously when deployment role is data_plane"
#     exit 1
# fi

# echo "passed: etcd should not be accessed anonymously when deployment role is data_plane"


# echo '
# deployment:
#     role: data_plane
#     role_data_plane:
#         config_provider: etcd
#         etcd:
#             user: reader
#             password: readerpw
#             host:
#                 - https://127.0.0.1:12379
#             prefix: "/apisix"
#             timeout: 30
# ' > conf/config.yaml

# echo '
# version: "3.7"

# services:
#   etcd0:
#     image: "gcr.io/etcd-development/etcd:v3.4.15"
#     container_name: etcd0
#     ports:
#       - "23790:2379"
#     environment:
#       - ALLOW_NONE_AUTHENTICATION=no
#       - ETCD_ADVERTISE_CLIENT_URLS=http://etcd0:2379
#       - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
#       - ETCD_ROOT_PASSWORD=root
# ' > t/cli/docker-compose-etcd-data-plane.yaml
# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml up -d
# sleep 3
# # create read only user and role
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root user add reader:readerpw
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root role add reader-role
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root role grant-permission reader-role --prefix=true read /
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root user grant-role reader reader-role

# out=$(make run 2>&1 || true)
# make stop
# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml down
# if ! echo "$out" | grep 'run -> [ Done ]'; then
#     echo "failed: should start data plane with read only user"
#     exit 1
# fi

# echo "passed: should start data plane with read only user"


# echo '
# deployment:
#     role: data_plane
#     role_data_plane:
#         config_provider: etcd
#     etcd:
#         user: writer
#         password: writer
#         host:
#             - https://127.0.0.1:12379
#         prefix: "/apisix"
#         timeout: 30
# ' > conf/config.yaml

# echo '
# version: "3.7"

# services:
#   etcd0:
#     image: "gcr.io/etcd-development/etcd:v3.4.15"
#     container_name: etcd0
#     ports:
#       - "23790:2379"
#     environment:
#       - ALLOW_NONE_AUTHENTICATION=no
#       - ETCD_ADVERTISE_CLIENT_URLS=http://etcd0:2379
#       - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
#       - ETCD_ROOT_PASSWORD=root
# ' > t/cli/docker-compose-etcd-data-plane.yaml

# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml up -d
# sleep 3

# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root user add writer:writerpw
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root role add writer-role
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root role grant-permission writer-role --prefix=true readwrite /
# etcdctl --endpoints=http://127.0.0.1:23790 --user=root:root user grant-role writer writer-role

# out=$(make run 2>&1 || true)
# make stop
# docker compose -f t/cli/docker-compose-etcd-data-plane.yaml down
# if ! echo "$out" | grep 'data plane role should not have write permission to etcd'; then
#     echo "failed: data plane role should not have write permission to etcd"
#     exit 1
# fi

# echo "passed: data plane role should not have write permission to etcd"
