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

# check admin https enabled

git checkout conf/config.yaml

echo "
apisix:
    admin_api_mtls:
        admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
        admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
    port_admin: 9180
    https_admin: true
" > conf/config.yaml

make init

grep "listen 9180 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to enabled https for admin"
    exit 1
fi

make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: failed to enabled https for admin"
    exit 1
fi

make stop

echo "passed: admin https enabled"

# rollback to the default

git checkout conf/config.yaml

make init

set +ex

grep "listen 9080 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 1 ]; then
    echo "failed: failed to rollback to the default admin config"
    exit 1
fi

set -ex

echo "passed: rollback to the default admin config"

# set allow_admin in conf/config.yaml

echo "
apisix:
    allow_admin:
        - 127.0.0.9
" > conf/config.yaml

make init

count=`grep -c "allow 127.0.0.9" conf/nginx.conf`
if [ $count -eq 0 ]; then
    echo "failed: not found 'allow 127.0.0.9;' in conf/nginx.conf"
    exit 1
fi

echo "
apisix:
    allow_admin: ~
" > conf/config.yaml

make init

count=`grep -c "allow all;" conf/nginx.conf`
if [ $count -eq 0 ]; then
    echo "failed: not found 'allow all;' in conf/nginx.conf"
    exit 1
fi

echo "passed: empty allow_admin in conf/config.yaml"

# missing admin key, allow any IP to access admin api

git checkout conf/config.yaml

echo '
apisix:
  allow_admin: ~
  admin_key: ~
' > conf/config.yaml

make init > output.log 2>&1 | true

grep -E "ERROR: missing valid Admin API token." output.log > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: should show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

echo "pass: missing admin key and show ERROR message"

# admin api, allow any IP but use default key

echo '
apisix:
  allow_admin: ~
  admin_key:
    -
      name: "admin"
      key: edd1c9f034335f136f87ad84b625c8f1
      role: admin
' > conf/config.yaml

make init > output.log 2>&1 | true

grep -E "WARNING: using fixed Admin API token has security risk." output.log > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: need to show `WARNING: using fixed Admin API token has security risk`"
    exit 1
fi

echo "pass: show WARNING message if the user used default token and allow any IP to access"

# port_admin set
echo '
apisix:
  port_admin: 9180
' > conf/config.yaml

rm logs/error.log
make init
make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: failed to access admin"
    exit 1
fi

if grep -E 'using uninitialized ".+" variable while logging request' logs/error.log; then
    echo "failed: uninitialized variable found during writing access log"
    exit 1
fi

echo "pass: uninitialized variable not found during writing access log (port_admin set)"

# Admin API can only be used with etcd config_center
echo '
apisix:
    enable_admin: true
    config_center: yaml
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "Admin API can only be used with etcd config_center"; then
    echo "failed: Admin API can only be used with etcd config_center"
    exit 1
fi

echo "passed: Admin API can only be used with etcd config_center"
