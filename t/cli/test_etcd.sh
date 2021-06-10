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

# check etcd while enable auth
git checkout conf/config.yaml

export ETCDCTL_API=3
etcdctl version
etcdctl --endpoints=127.0.0.1:2379 user add "root:apache-api6"
etcdctl --endpoints=127.0.0.1:2379 role add root
etcdctl --endpoints=127.0.0.1:2379 user grant-role root root
etcdctl --endpoints=127.0.0.1:2379 user get root
etcdctl --endpoints=127.0.0.1:2379 auth enable
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 del /apisix --prefix

echo '
etcd:
  host:
    - "http://127.0.0.1:2379"
  prefix: "/apisix"
  timeout: 30
  user: root
  password: apache-api6
' > conf/config.yaml

make init
cmd_res=`etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 get /apisix --prefix`
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 auth disable
etcdctl --endpoints=127.0.0.1:2379 role delete root
etcdctl --endpoints=127.0.0.1:2379 user delete root

init_kv=(
"/apisix/consumers/ init_dir"
"/apisix/global_rules/ init_dir"
"/apisix/plugin_metadata/ init_dir"
"/apisix/plugins/ init_dir"
"/apisix/proto/ init_dir"
"/apisix/routes/ init_dir"
"/apisix/services/ init_dir"
"/apisix/ssl/ init_dir"
"/apisix/stream_routes/ init_dir"
"/apisix/upstreams/ init_dir"
)

IFS=$'\n'
for kv in ${init_kv[@]}
do
count=`echo $cmd_res | grep -c ${kv} || true`
if [ $count -ne 1 ]; then
    echo "failed: failed to match ${kv}"
    exit 1
fi
done

echo "passed: etcd auth enabled and init kv has been set up correctly"

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'authentication is not enabled'; then
    echo "failed: properly handle the error when connecting to etcd without auth"
    exit 1
fi

echo "passed: properly handle the error when connecting to etcd without auth"

# Check etcd retry if connect failed
git checkout conf/config.yaml

echo '
etcd:
  host:
    - "http://127.0.0.1:2389"
  prefix: "/apisix"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "retry time"; then
    echo "failed: apisix should echo \"retry time\""
    exit 1
fi

echo "passed: Show retry time info successfully"

# Check etcd connect refused
git checkout conf/config.yaml

echo '
etcd:
  host:
    - "http://127.0.0.1:2389"
  prefix: "/apisix"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "connection refused"; then
    echo "failed: apisix should echo \"connection refused\""
    exit 1
fi

echo "passed: Show connection refused info successfully"

# Check etcd auth error
git checkout conf/config.yaml

export ETCDCTL_API=3
etcdctl version
etcdctl --endpoints=127.0.0.1:2379 user add "root:apache-api6"
etcdctl --endpoints=127.0.0.1:2379 role add root
etcdctl --endpoints=127.0.0.1:2379 user grant-role root root
etcdctl --endpoints=127.0.0.1:2379 user get root
etcdctl --endpoints=127.0.0.1:2379 auth enable
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 del /apisix --prefix

echo '
etcd:
  host:
    - "http://127.0.0.1:2379"
  prefix: "/apisix"
  timeout: 30
  user: root
  password: apache-api7
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "invalid user ID or password"; then
    echo "failed: should echo \"invalid user ID or password\""
    exit 1
fi

echo "passed: show password error successfully"

# clean etcd auth
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 auth disable
etcdctl --endpoints=127.0.0.1:2379 role delete root
etcdctl --endpoints=127.0.0.1:2379 user delete root
