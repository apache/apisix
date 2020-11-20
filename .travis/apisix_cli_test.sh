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

set -ex

clean_up() {
    git checkout conf/config.yaml
}

trap clean_up EXIT

git checkout conf/config.yaml

# check 'Server: APISIX' is not in nginx.conf. We already added it in Lua code.
make init

if grep "Server: APISIX" conf/nginx.conf > /dev/null; then
    echo "failed: 'Server: APISIX' should not be added twice"
    exit 1
fi

echo "passed: 'Server: APISIX' not in nginx.conf"

#make init <- no need to re-run since we don't change the config yet.

# check the error_log directive uses warn level by default.
if ! grep "error_log logs/error.log warn;" conf/nginx.conf > /dev/null; then
    echo "failed: error_log directive doesn't use warn level by default"
    exit 1
fi

echo "passed: error_log directive uses warn level by default"

# check whether the 'reuseport' is in nginx.conf .

grep -E "listen 9080.*reuseport" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: nginx.conf file is missing reuseport configuration"
    exit 1
fi

echo "passed: nginx.conf file contains reuseport configuration"

# check default ssl port
echo "
apisix:
    ssl:
        listen_port: 8443
" > conf/config.yaml

make init

grep "listen 8443 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to update ssl port"
    exit 1
fi

grep "listen \[::\]:8443 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to update ssl port"
    exit 1
fi

echo "passed: change default ssl port"

# check support multiple ports listen in http and https

echo "
apisix:
  node_listen:
    - 9080
    - 9081
    - 9082
  ssl:
    listen_port:
      - 9443
      - 9444
      - 9445
" > conf/config.yaml

make init

count_http_ipv4=`grep -c "listen 908." conf/nginx.conf || true`
if [ $count_http_ipv4 -ne 3 ]; then
    echo "failed: failed to support multiple ports listen in http with ipv4"
    exit 1
fi

count_http_ipv6=`grep -c "listen \[::\]:908." conf/nginx.conf || true`
if [ $count_http_ipv6 -ne 3 ]; then
    echo "failed: failed to support multiple ports listen in http with ipv6"
    exit 1
fi

count_https_ipv4=`grep -c "listen 944. ssl" conf/nginx.conf || true`
if [ $count_https_ipv4 -ne 3 ]; then
    echo "failed: failed to support multiple ports listen in https with ipv4"
    exit 1
fi

count_https_ipv6=`grep -c "listen \[::\]:944. ssl" conf/nginx.conf || true`
if [ $count_https_ipv6 -ne 3 ]; then
    echo "failed: failed to support multiple ports listen in https with ipv6"
    exit 1
fi

echo "passed: support multiple ports listen in http and https"

# check default env
echo "
nginx_config:
    envs:
        - TEST
" > conf/config.yaml

make init

grep "env TEST;" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to update env"
    exit 1
fi

echo "passed: change default env"

# check nameserver imported
git checkout conf/config.yaml

make init

i=`grep  -E '^nameserver[[:space:]]+(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4]0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])[[:space:]]?$' /etc/resolv.conf | awk '{print $2}'`
for ip in $i
do
  echo $ip
  grep $ip conf/nginx.conf > /dev/null
  if [ ! $? -eq 0 ]; then
    echo "failed: system DNS "$ip" unimported"
    exit 1
  fi
done

echo "passed: system nameserver imported"

# enable enable_dev_mode
git checkout conf/config.yaml

echo "
apisix:
    enable_dev_mode: true
" > conf/config.yaml

make init

count=`grep -c "worker_processes 1;" conf/nginx.conf`
if [ $count -ne 1 ]; then
    echo "failed: worker_processes is not 1 when enable enable_dev_mode"
    exit 1
fi

count=`grep -c "listen 9080.*reuseport" conf/nginx.conf || true`
if [ $count -ne 0 ]; then
    echo "failed: reuseport should be disabled when enable enable_dev_mode"
    exit 1
fi

echo "passed: enable enable_dev_mode"

# check whether the 'worker_cpu_affinity' is in nginx.conf

git checkout conf/config.yaml

make init

grep -E "worker_cpu_affinity" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: nginx.conf file is missing worker_cpu_affinity configuration"
    exit 1
fi

echo "passed: nginx.conf file contains worker_cpu_affinity configuration"

# check admin https enabled

git checkout conf/config.yaml

echo "
apisix:
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

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
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

grep "listen 9180 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 1 ]; then
    echo "failed: failed to rollback to the default admin config"
    exit 1
fi

set -ex

echo "passed: rollback to the default admin config"

# check the 'worker_shutdown_timeout' in 'nginx.conf' .

make init

grep -E "worker_shutdown_timeout 240s" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: worker_shutdown_timeout in nginx.conf is required 240s"
    exit 1
fi

echo "passed: worker_shutdown_timeout in nginx.conf is ok"

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

# check the 'client_max_body_size' in 'nginx.conf' .

git checkout conf/config.yaml
sed -i 's/client_max_body_size: 0/client_max_body_size: 512m/'  conf/config-default.yaml

make init

if ! grep -E "client_max_body_size 512m" conf/nginx.conf > /dev/null; then
    echo "failed: client_max_body_size in nginx.conf doesn't change"
    exit 1
fi

echo "passed: client_max_body_size in nginx.conf is ok"

git checkout conf/config-default.yaml

# check worker processes number is configurable.

git checkout conf/config.yaml

echo "
nginx_config:
    worker_processes: 2
" > conf/config.yaml

make init

grep "worker_processes 2;" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: worker_processes in nginx.conf doesn't change"
    exit 1
fi

sed -i 's/worker_processes: 2/worker_processes: auto/'  conf/config.yaml
echo "passed: worker_processes number is configurable"

# log format

git checkout conf/config.yaml

echo '
nginx_config:
  http:
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host test_access_log_format"
' > conf/config.yaml

make init

grep "test_access_log_format" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: access_log_format in nginx.conf doesn't change"
    exit 1
fi

git checkout conf/config.yaml

echo "passed: worker_processes number is configurable"

# missing admin key, allow any IP to access admin api

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

# allow to merge configuration without middle layer

git checkout conf/config.yaml

echo '
nginx_config:
  http:
    lua_shared_dicts:
      my_dict: 1m
' > conf/config.yaml

make init

if ! grep "lua_shared_dict my_dict 1m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'my_dict' not in nginx.conf"
    exit 1
fi

echo "passed: found 'my_dict' in nginx.conf"

# check disable cpu affinity
git checkout conf/config.yaml

echo '
nginx_config:
  enable_cpu_affinity: false
' > conf/config.yaml

make init

count=`grep -c "worker_cpu_affinity" conf/nginx.conf  || true`
if [ $count -ne 0 ]; then
    echo "failed: nginx.conf file found worker_cpu_affinity when disable it"
    exit 1
fi

echo "passed: nginx.conf file disable cpu affinity"

# set worker processes with env
git checkout conf/config.yaml

export APISIX_WORKER_PROCESSES=8

make init

count=`grep -c "worker_processes 8;" conf/nginx.conf || true`
if [ $count -ne 1 ]; then
    echo "failed: worker_processes is not 8 when using env to set worker processes"
    exit 1
fi

echo "passed: using env to set worker processes"

# set worker processes with env
git checkout conf/config.yaml

make init

count=`grep -c "ssl_session_tickets off;" conf/nginx.conf || true `
if [ $count -eq 0 ]; then
    echo "failed: ssl_session_tickets is off when ssl.ssl_session_tickets is false."
    exit 1
fi

sed -i 's/ssl_session_tickets: false/ssl_session_tickets: true/' conf/config-default.yaml
make init

count=`grep -c "ssl_session_tickets on;" conf/nginx.conf || true `
if [ $count -eq 0 ]; then
    echo "failed: ssl_session_tickets is on when ssl.ssl_session_tickets is true."
    exit 1
fi

echo "passed: disable ssl_session_tickets by default"

# access log with JSON format

echo '
nginx_config:
  http:
    access_log_format: |-
      {"@timestamp": "$time_iso8601", "client_ip": "$remote_addr", "status": "$status"}
    access_log_format_escape: json
' > conf/config.yaml

make init
make run
sleep 0.1
curl http://127.0.0.1:9080/hello2
sleep 4
tail -n 1 logs/access.log > output.log

if [ `grep -c '"client_ip": "127.0.0.1"' output.log` -eq '0' ]; then
    echo "failed: invalid JSON log in access log"
    exit 1
fi

if [ `grep -c 'main escape=json' conf/nginx.conf` -eq '0' ]; then
    echo "failed: not found \"escape=json\" in conf/nginx.conf"
    exit 1
fi

make stop

echo "passed: access log with JSON format"

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
/apisix/consumers/
init_dir
/apisix/global_rules/
init_dir
/apisix/node_status/
init_dir
/apisix/plugin_metadata/
init_dir
/apisix/plugins/
init_dir
/apisix/proto/
init_dir
/apisix/routes/
init_dir
/apisix/services/
init_dir
/apisix/ssl/
init_dir
/apisix/stream_routes/
init_dir
/apisix/upstreams/
init_dir
)
i=0

for kv in $cmd_res
do
    if [ "${init_kv[$i]}" != "$kv" ]; then
        echo "failed: index=$i, $kv is not equal to ${init_kv[$i]}"
        exit 1
    fi
    let i=$i+1
done

echo "passed: etcd auth enabled and init kv has been set up correctly"
