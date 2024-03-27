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

# check restart with old nginx.pid exist
echo "-1" > logs/nginx.pid
out=$(./bin/apisix start 2>&1 || true)
if echo "$out" | grep "the old APISIX is still running"; then
    rm logs/nginx.pid
    echo "failed: should reject bad nginx.pid"
    exit 1
fi

./bin/apisix stop
sleep 0.5
rm logs/nginx.pid || true

# check no corresponding process
make run
oldpid=$(< logs/nginx.pid)
make stop
sleep 0.5
echo $oldpid > logs/nginx.pid
out=$(make run || true)
if ! echo "$out" | grep "nginx.pid exists but there's no corresponding process with pid"; then
    echo "failed: should find no corresponding process"
    exit 1
fi
make stop
echo "pass: no corresponding process"

# check running when run repeatedly
out=$(make run; make run || true)
if ! echo "$out" | grep "the old APISIX is still running"; then
    echo "failed: should find APISIX running"
    exit 1
fi

make stop
echo "pass: check APISIX running"

# check customized config

git checkout conf/config.yaml

# start with not existed customized config
make init

if ./bin/apisix start -c conf/not_existed_config.yaml; then
    echo "failed: apisix still start with invalid customized config.yaml"
    exit 1
fi

# start with customized config
echo "
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
" > conf/customized_config.yaml

./bin/apisix start -c conf/customized_config.yaml

# check if .customized_config_path has been created
if [ ! -e conf/.customized_config_path ]; then
    rm conf/customized_config.yaml
    echo ".customized_config_path should exits"
    exit 1
fi

get_admin_key() {
local admin_key=$(grep "key:" -A3 conf/config.yaml | grep "key: *" | awk '{print $2}')
echo "$admin_key"
}
admin_key=$(get_admin_key); echo $admin_key

# check if the custom config is used
code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
if [ ! $code -eq 200 ]; then
    rm conf/customized_config.yaml
    echo "failed: customized config.yaml not be used"
    exit 1
fi

make stop

# check if .customized_config_path has been removed
if [ -e conf/.customized_config_path ]; then
    rm conf/customized_config_path.yaml
    echo ".customized_config_path should be removed"
    exit 1
fi

# start with invalied config
echo "abc" > conf/customized_config.yaml

if ./bin/apisix start -c conf/customized_config.yaml ; then
    rm conf/customized_config.yaml
    echo "start should be failed"
    exit 1
fi

# check if apisix can be started use correctly default config. (https://github.com/apache/apisix/issues/9700)
./bin/apisix start

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
if [ ! $code -eq 200 ]; then
    rm conf/customized_config.yaml
    echo "failed: should use default config"
    exit 1
fi

make stop

# check if apisix can be started after multiple start failures. (https://github.com/apache/apisix/issues/9171)
echo "
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
    etcd:
        host:
         - http://127.0.0.1:22379
" > conf/customized_config.yaml

./bin/apisix start -c conf/customized_config.yaml || true
./bin/apisix start -c conf/customized_config.yaml || true
./bin/apisix start -c conf/customized_config.yaml || true

echo "
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
" > conf/customized_config.yaml

./bin/apisix start -c conf/customized_config.yaml

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
if [ ! $code -eq 200 ]; then
    rm conf/customized_config.yaml
    echo "failed: should use default config"
    exit 1
fi

rm conf/customized_config.yaml
echo "passed: test customized config successful"

# test quit command
bin/apisix start

if ! ps -ef | grep "apisix" | grep "master process" | grep -v "grep"; then
    echo "apisix not started"
    exit 1
fi

bin/apisix quit

sleep 2

if ps -ef | grep "worker process is shutting down" | grep -v "grep"; then
    echo "all workers should exited"
    exit 1
fi

echo "passed: test quit command successful"

# test reload command
bin/apisix start

if ! ps -ef | grep "apisix" | grep "master process" | grep -v "grep"; then
    echo "apisix not started"
    exit 1
fi

bin/apisix reload

sleep 3

if ps -ef | grep "worker process is shutting down" | grep -v "grep"; then
    echo "old workers should exited"
    exit 1
fi

echo "passed: test reload command successful"
