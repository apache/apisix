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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf

. ./t/cli/common.sh

exit_if_not_customed_nginx

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
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - http://127.0.0.1:2379
    prefix: /apisix
    timeout: 30
    use_grpc: true
    user: root
    password: apache-api6
' > conf/config.yaml

make run
sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: could not work with etcd"
    exit 1
fi

echo "passed: work well with etcd auth enabled"

etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6 auth disable
etcdctl --endpoints=127.0.0.1:2379 role delete root
etcdctl --endpoints=127.0.0.1:2379 user delete root

# check connect to etcd with ipv6 address in cli
git checkout conf/config.yaml

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - http://[::1]:2379
    prefix: /apisix
    use_grpc: true
    timeout: 30
' > conf/config.yaml

rm logs/error.log || true
make run
sleep 0.1

if grep "update endpoint: http://\[::1\]:2379 to unhealthy" logs/error.log; then
    echo "failed: connect to etcd via ipv6 address failed"
    exit 1
fi

if grep "host or service not provided, or not known" logs/error.log; then
    echo "failed: luasocket resolve ipv6 addresses failed"
    exit 1
fi

make stop

echo "passed: connect to etcd via ipv6 address successfully"
