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

etcdctl user add root <<EOF
test
test
EOF
etcdctl role add root
etcdctl user grant-role root root
# add readonly user
etcdctl user add apisix-data-plane <<EOF
test
test
EOF
etcdctl role add data-plane-role
etcdctl role grant-permission --prefix=true data-plane-role read /apisix
etcdctl user grant-role apisix-data-plane data-plane-role

etcdctl auth enable

# data_plane can start with readonly etcd user
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - https://127.0.0.1:12379
        user: apisix-data-plane
        password: test
        prefix: "/apisix"
        timeout: 30
        tls:
            verify: false
' > conf/config.yaml

make run

sleep 1

res=$(etcdctl -u root:test get / --prefix | wc -l)

if [ ! $res -eq 0 ]; then
    echo "failed: data_plane should not write data to etcd"
    exit 1
fi

echo "passed: data_plane does not write data to etcd"

etcdctl -u root:test user remove apisix-data-plane
etcdctl -u root:test role remove data-plane-role
etcdctl -u root:test user remove root
etcdctl -u root:test role remove root
etcdctl -u root:test auth disable
