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
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
" > conf/config.yaml

make init

grep "listen 0.0.0.0:9180 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to enable https for admin"
    exit 1
fi

make run

get_admin_key() {
wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
local admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml)
echo "$admin_key"
}
export admin_key=$(get_admin_key); echo $admin_key

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
if [ ! $code -eq 200 ]; then
    echo "failed: failed to enable https for admin"
    exit 1
fi

make stop

echo "passed: admin https enabled"

echo '
apisix:
  enable_admin: true
deployment:
  admin:
    admin_listen:
      ip: 127.0.0.2
      port: 9181
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.2:9181;" conf/nginx.conf > /dev/null; then
    echo "failed: customize address for admin server"
    exit 1
fi

make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.2:9181/apisix/admin/routes -H "X-API-KEY: $admin_key")

if [ ! $code -eq 200 ]; then
    echo "failed: failed to access admin"
    exit 1
fi

make stop

# rollback to the default

git checkout conf/config.yaml

make init

set +ex

grep "listen 0.0.0.0:9080 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 1 ]; then
    echo "failed: failed to rollback to the default admin config"
    exit 1
fi

set -ex

echo "passed: rollback to the default admin config"

# set allow_admin in conf/config.yaml

echo "
deployment:
    admin:
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
deployment:
    admin:
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
deployment:
  admin:
    admin_key: ~
    allow_admin: ~
' > conf/config.yaml

make init > output.log 2>&1 | true

grep -E "ERROR: missing valid Admin API token." output.log > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: should show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

echo "pass: missing admin key and show ERROR message"

# missing admin key, only allow 127.0.0.0/24 to access admin api

echo '
deployment:
  admin:
    admin_key: ~
    allow_admin:
      - 127.0.0.0/24
' > conf/config.yaml

make init > output.log 2>&1 | true

if grep -E "ERROR: missing valid Admin API token." output.log > /dev/null; then
    echo "failed: should not show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

echo '
deployment:
  admin:
    admin_key: ~
    allow_admin:
      - 0.0.0.0/0
      - 127.0.0.0/24
' > conf/config.yaml

make init > output.log 2>&1 | true

if ! grep -E "ERROR: missing valid Admin API token." output.log > /dev/null; then
    echo "failed: should show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

echo "pass: missing admin key and only allow 127.0.0.0/24 to access admin api"

# allow any IP to access admin api with empty admin_key, when admin_key_required=true

git checkout conf/config.yaml

echo '
deployment:
  admin:
    admin_key_required: true
    admin_key: ~
    allow_admin:
      - 0.0.0.0/0
' > conf/config.yaml

make init > output.log 2>&1 | true

if ! grep -E "ERROR: missing valid Admin API token." output.log > /dev/null; then
    echo "failed: should show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

echo '
deployment:
  admin:
    admin_key_required: false
    admin_key: ~
    allow_admin:
      - 0.0.0.0/0
' > conf/config.yaml

make init > output.log 2>&1 | true

if grep -E "ERROR: missing valid Admin API token." output.log > /dev/null; then
    echo "failed: should not show 'ERROR: missing valid Admin API token.'"
    exit 1
fi

if ! grep -E "Warning! Admin key is bypassed" output.log > /dev/null; then
    echo "failed: should show 'Warning! Admin key is bypassed'"
    exit 1
fi

echo '
deployment:
  admin:
    admin_key_required: invalid-value
' > conf/config.yaml

make init > output.log 2>&1 | true

if grep -E "path[deployment->admin->admin_key_required] expect: boolean, but got: string" output.log > /dev/null; then
    echo "check admin_key_required value failed: should show 'expect: boolean, but got: string'"
    exit 1
fi

echo "pass: allow empty admin_key, when admin_key_required=false"

# admin api, allow any IP but use default key

echo '
deployment:
  admin:
    allow_admin: ~
    admin_key:
        -
        name: "admin"
        key: ''
        role: admin
' > conf/config.yaml

make init > output.log 2>&1 | true

grep -E "WARNING: using empty Admin API. This will trigger APISIX to automatically generate a random Admin API token." output.log > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: need to show `WARNING: using fixed Admin API token has security risk`"
    exit 1
fi

echo "pass: show WARNING message if the user uses empty key"

# admin_listen set
echo '
deployment:
  admin:
    admin_listen:
      port: 9180
' > conf/config.yaml

rm logs/error.log
make init
make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: failed to access admin"
    exit 1
fi

if grep -E 'using uninitialized ".+" variable while logging request' logs/error.log; then
    echo "failed: uninitialized variable found during writing access log"
    exit 1
fi

echo "pass: uninitialized variable not found during writing access log (admin_listen set)"

# Admin API can only be used with etcd config_provider
## if role is data_plane, and config_provider is yaml, then enable_admin is set to false
echo '
apisix:
    enable_admin: true
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
' > conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep "Admin API can only be used with etcd config_provider"; then
    echo "failed: Admin API can only be used with etcd config_provider"
    exit 1
fi

echo "passed: Admin API can only be used with etcd config_provider"

# disable Admin API and init plugins syncer
echo '
apisix:
  enable_admin: false
' > conf/config.yaml

rm logs/error.log
make init
make run

make init

if grep -E "failed to fetch data from etcd" logs/error.log; then
    echo "failed: should sync /apisix/plugins from etcd when disabling admin normal"
    exit 1
fi

make stop

echo "pass: sync /apisix/plugins from etcd when disabling admin successfully"



# ignore changes to /apisix/plugins/ due to init_etcd
echo '
apisix:
  enable_admin: true
plugins:
  - public-api
  - node-status
nginx_config:
  error_log_level:  info
' > conf/config.yaml

rm logs/error.log
make init
make run

# initialize node-status public API routes #1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} -X PUT http://127.0.0.1:9180/apisix/admin/routes/node-status \
    -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
    -d "{
        \"uri\": \"/apisix/status\",
        \"plugins\": {
            \"public-api\": {}
        }
    }")
if [ ! $code -lt 300 ]; then
    echo "failed: initialize node status public API failed #1"
    exit 1
fi

sleep 0.5

# first time check node status api
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/status)
if [ ! $code -eq 200 ]; then
    echo "failed: first time check node status api failed #1"
    exit 1
fi

# mock another instance init etcd dir
make init
sleep 1

# initialize node-status public API routes #2
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} -X PUT http://127.0.0.1:9180/apisix/admin/routes/node-status \
    -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
    -d "{
        \"uri\": \"/apisix/status\",
        \"plugins\": {
            \"public-api\": {}
        }
    }")
if [ ! $code -eq 200 ]; then
    echo "failed: initialize node status public API failed #2"
    exit 1
fi

sleep 0.5

# second time check node status api
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/status)
if [ ! $code -eq 200 ]; then
    echo "failed: second time check node status api failed #1"
    exit 1
fi

make stop

echo "pass: ignore changes to /apisix/plugins/ due to init_etcd successfully"


# accept changes to /apisix/plugins when enable_admin is false
echo '
apisix:
  enable_admin: false
plugins:
  - public-api
  - node-status
stream_plugins:
' > conf/config.yaml

rm logs/error.log
make init
make run

# first time check node status api
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/status)
if [ ! $code -eq 200 ]; then
    echo "failed: first time check node status api failed #2"
    exit 1
fi

sleep 0.5

# check http plugins load list
if ! grep logs/error.log -E -e 'new plugins: {"public-api":true,"node-status":true}' \
   -e 'new plugins: {"node-status":true,"public-api":true}'; then
    echo "failed: first time load http plugins list failed"
    exit 1
fi

# check stream plugins(no plugins under stream, it will be added below)
if grep -E 'failed to read stream plugin list from local file' logs/error.log; then
    echo "failed: first time load stream plugins list failed"
    exit 1
fi

# mock another instance add /apisix/plugins
res=$(etcdctl put "/apisix/plugins" '[{"name":"node-status"},{"name":"example-plugin"},{"name":"public-api"},{"stream":true,"name":"mqtt-proxy"}]')
if [[ $res != "OK" ]]; then
    echo "failed: failed to set /apisix/plugins to add more plugins"
    exit 1
fi

sleep 0.5

# second time check node status api
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/status)
if [ ! $code -eq 200 ]; then
    echo "failed: second time check node status api failed #2"
    exit 1
fi

# check http plugins load list
if ! grep logs/error.log -E -e 'new plugins: {"public-api":true,"node-status":true}' \
   -e 'new plugins: {"node-status":true,"public-api":true}'; then
    echo "failed: second time load http plugins list failed"
    exit 1
fi

# check stream plugins load list
if ! grep -E 'new plugins: {.*example-plugin' logs/error.log; then
    echo "failed: second time load stream plugins list failed"
    exit 1
fi


if grep -E 'new plugins: {}' logs/error.log; then
    echo "failed: second time load plugins list failed"
    exit 1
fi

make stop

echo "pass: accept changes to /apisix/plugins successfully"
