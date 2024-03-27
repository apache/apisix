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

# HTTP
echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
' > conf/config.yaml

make run
sleep 1

get_admin_key() {
local admin_key=$(grep "key:" -A3 conf/config.yaml | grep "key: *" | awk '{print $2}')
echo "$admin_key"
}
export admin_key=$(get_admin_key); echo $admin_key

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: could not connect to etcd with http enabled"
    exit 1
fi

# Both HTTP and Stream
echo '
apisix:
    proxy_mode: http&stream
    enable_admin: true
    stream_proxy:
        tcp:
            - addr: 9100
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
' > conf/config.yaml

make run
sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: could not connect to etcd with http & stream enabled"
    exit 1
fi

# Stream
echo '
apisix:
    enable_admin: false
    proxy_mode: stream
    stream_proxy:
        tcp:
            - addr: 9100
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
' > conf/config.yaml

make run
sleep 1
make stop

if grep '\[error\]' logs/error.log; then
    echo "failed: could not connect to etcd with stream enabled"
    exit 1
fi

echo "passed: could connect to etcd"

echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        host:
            - "https://admin.apisix.dev:22379"
        prefix: "/apisix"
        tls:
            verify: false
  ' > conf/config.yaml

out=$(make init 2>&1 || echo "ouch")
if ! echo "$out" | grep "bad certificate"; then
    echo "failed: apisix should echo \"bad certificate\""
    exit 1
fi

echo "passed: certificate verify fail expectedly"
