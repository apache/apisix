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

# add root user to help disable auth
etcdctl user add "root:test"
etcdctl role add root
etcdctl user grant-role root root
# add readonly user
etcdctl user add "apisix-data-plane:test"
etcdctl role add data-plane-role
etcdctl role grant-permission --prefix=true data-plane-role read /apisix
etcdctl user grant-role apisix-data-plane data-plane-role
# enable auth
etcdctl auth enable

# data_plane can start with read-only etcd
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - http://127.0.0.1:2379
        user: apisix-data-plane
        password: test
        prefix: /apisix
        timeout: 30
' > conf/config.yaml

out=$(make init 2>&1 || true)
sleep 3

if echo "$out" | grep 'etcdserver: permission denied'; then
    echo "failed: data_plane should not write data to etcd"
    exit 1
fi

echo "passed: data_plane can init with read-only etcd"

# clean up
etcdctl --user=root:test auth disable
etcdctl user delete apisix-data-plane
etcdctl role delete data-plane-role
etcdctl user delete root
etcdctl role delete root
