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
