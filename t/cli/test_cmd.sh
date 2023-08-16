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

# remove stale conf server sock
touch conf/config_listen.sock
./bin/apisix start
sleep 0.5
./bin/apisix stop
sleep 0.5

if [ -e conf/config_listen.sock ]; then
    echo "failed: should remove stale conf server sock"
    exit 1
fi

# don't remove stale conf server sock when APISIX is running
./bin/apisix start
sleep 0.5
./bin/apisix start
sleep 0.5

if [ ! -e conf/config_listen.sock ]; then
    echo "failed: should not remove stale conf server sock"
    exit 1
fi

./bin/apisix stop
sleep 0.5

echo "passed: stale conf server sock removed"

# check restart with old nginx.pid exist
echo "-1" > logs/nginx.pid
out=$(./bin/apisix start 2>&1 || true)
if echo "$out" | grep "APISIX is running"; then
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
if ! echo "$out" | grep "APISIX is running"; then
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
    echo ".config_path file should exits"
    exit 1
fi

# check if the custom config is used
code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    rm conf/customized_config.yaml
    echo "failed: customized config.yaml not be used"
    exit 1
fi

make stop

# check if .customized_config_path has been removed
if [ -e conf/.config_path ]; then
    rm conf/customized_config_path.yaml
    echo ".config_path file should be removed"
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

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
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

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    rm conf/customized_config.yaml
    echo "failed: should use default config"
    exit 1
fi

rm conf/customized_config.yaml
echo "passed: test customized config successful"
