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

# check customized config.yaml is copied and reverted.

git checkout conf/config.yaml

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

cp conf/config.yaml conf/config_original.yaml

make init

if ./bin/apisix start -c conf/not_existed_config.yaml; then
    echo "failed: apisix still start with invalid customized config.yaml"
    exit 1
fi

./bin/apisix start -c conf/customized_config.yaml

if cmp -s "conf/config.yaml" "conf/config_original.yaml"; then
    rm conf/config_original.yaml
    echo "failed: customized config.yaml copied failed"
    exit 1
fi

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    rm conf/config_original.yaml conf/customized_config.yaml
    echo "failed: customized config.yaml not be used"
    exit 1
fi

make stop

if ! cmp -s "conf/config.yaml" "conf/config_original.yaml"; then
    rm conf/config_original.yaml conf/customized_config.yaml
    echo "failed: customized config.yaml reverted failed"
    exit 1
fi

rm conf/config_original.yaml conf/customized_config.yaml
echo "passed: customized config.yaml copied and reverted succeeded"
