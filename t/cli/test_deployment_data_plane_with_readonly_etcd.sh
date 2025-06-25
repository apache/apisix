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

# non data_plane can prepare dirs when init etcd
echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        host:
            - http://127.0.0.1:2379
        prefix: /apisix
        timeout: 30
' >conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'prepare dirs'; then
    echo "failed: non data_plane should prepare dirs"
    exit 1
fi
echo "passed: non data_plane can prepare dirs when init etcd"

# start apisix to test non data_plane can work with etcd
make run
sleep 3

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -o /dev/null -s -w %{http_code} -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": ["
                return function(conf, ctx)
                    local core = require(\"apisix.core\")
                    return core.response.exit(200)
                end
            "]
        }
    }
}'

# check can access the route
code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)
if [ ! "$code" -eq 200 ]; then
    echo "failed: non data_plane should be able to access the route"
    exit 1
fi

echo "passed: non data_plane can work with etcd"

# prepare for data_plane with etcd
# stop apisix
make stop
sleep 3

# data_plane can skip prepare dirs when init with etcd
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - http://127.0.0.1:2379
        prefix: /apisix
        timeout: 30
' >conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep 'prepare dirs'; then
    echo "failed: data_plane should not prepare dirs"
    exit 1
fi
if ! echo "$out" | grep 'data plane does not have write permissions, skip preparing dirs'; then
    echo "failed: data_plane should skip preparing dirs"
    exit 1
fi
echo "passed: data_plane can skip prepare dirs when init with etcd"

# start apisix to test data_plane can work with etcd
make run
sleep 3

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)
if [ ! "$code" -eq 200 ]; then
    echo "failed: data_plane should be able to access the route"
    exit 1
fi
echo "passed: data_plane can work with etcd"

# prepare for data_plane with read-only etcd
# stop apisix
make stop
sleep 3
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

# data_plane can skip prepare dirs when init with read-only etcd
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
' >conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep 'prepare dirs'; then
    echo "failed: data_plane should not prepare dirs"
    exit 1
fi
if ! echo "$out" | grep 'data plane does not have write permissions, skip preparing dirs'; then
    echo "failed: data_plane should skip preparing dirs"
    exit 1
fi
echo "passed: data_plane can init with read-only etcd"

# start apisix to test data_plane can work with read-only etcd
make run
sleep 3

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)
if [ ! "$code" -eq 200 ]; then
    echo "failed: data_plane should be able to access the route with read-only etcd"
    exit 1
fi
echo "passed: data_plane can work with read-only etcd"

# clean up
etcdctl --user=root:test auth disable
etcdctl user delete apisix-data-plane
etcdctl role delete data-plane-role
etcdctl user delete root
etcdctl role delete root
