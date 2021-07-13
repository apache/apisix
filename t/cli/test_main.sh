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

# support environment variables
echo '
nginx_config:
    envs:
        - ${{var_test}}_${{FOO}}
' > conf/config.yaml

var_test=TEST FOO=bar make init

if ! grep "env TEST_bar;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables"
    exit 1
fi

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "can't find environment variable"; then
    echo "failed: failed to resolve variables"
    exit 1
fi

echo "passed: resolve variables"

echo '
nginx_config:
    worker_rlimit_nofile: ${{nofile9}}
' > conf/config.yaml

nofile9=99999 make init

if ! grep "worker_rlimit_nofile 99999;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables as integer"
    exit 1
fi

echo "passed: resolve variables as integer"

echo '
apisix:
    enable_admin: ${{admin}}
' > conf/config.yaml

admin=false make init

if grep "location /apisix/admin" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables as boolean"
    exit 1
fi

echo "passed: resolve variables as boolean"

echo '
nginx_config:
    envs:
        - ${{ var_test}}_${{ FOO }}
' > conf/config.yaml

var_test=TEST FOO=bar make init

if ! grep "env TEST_bar;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables wrapped with whitespace"
    exit 1
fi

echo "passed: resolve variables wrapped with whitespace"

# support environment variables in local_conf
echo '
etcd:
    host:
        - "http://${{ETCD_HOST}}:${{ETCD_PORT}}"
' > conf/config.yaml

ETCD_HOST=127.0.0.1 ETCD_PORT=2379 make init

if ! grep "env ETCD_HOST=127.0.0.1;" conf/nginx.conf > /dev/null; then
    echo "failed: support environment variables in local_conf"
    exit 1
fi

# don't override user's envs configuration
echo '
etcd:
    host:
        - "http://${{ETCD_HOST}}:${{ETCD_PORT}}"
nginx_config:
    envs:
        - ETCD_HOST
' > conf/config.yaml

ETCD_HOST=127.0.0.1 ETCD_PORT=2379 make init

if grep "env ETCD_HOST=127.0.0.1;" conf/nginx.conf > /dev/null; then
    echo "failed: support environment variables in local_conf"
    exit 1
fi

if ! grep "env ETCD_HOST;" conf/nginx.conf > /dev/null; then
    echo "failed: support environment variables in local_conf"
    exit 1
fi

echo '
etcd:
    host:
        - "http://${{ETCD_HOST}}:${{ETCD_PORT}}"
nginx_config:
    envs:
        - ETCD_HOST=1.1.1.1
' > conf/config.yaml

ETCD_HOST=127.0.0.1 ETCD_PORT=2379 make init

if grep "env ETCD_HOST=127.0.0.1;" conf/nginx.conf > /dev/null; then
    echo "failed: support environment variables in local_conf"
    exit 1
fi

if ! grep "env ETCD_HOST=1.1.1.1;" conf/nginx.conf > /dev/null; then
    echo "failed: support environment variables in local_conf"
    exit 1
fi

echo "pass: support environment variables in local_conf"

# support merging worker_processes
echo '
nginx_config:
    worker_processes: 1
' > conf/config.yaml

make init

if ! grep "worker_processes 1;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to merge worker_processes"
    exit 1
fi

echo '
nginx_config:
    worker_processes: ${{nproc}}
' > conf/config.yaml

nproc=1 make init

if ! grep "worker_processes 1;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to merge worker_processes"
    exit 1
fi

echo '
nginx_config:
    worker_processes: true
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'path\[nginx_config->worker_processes\] expect'; then
    echo "failed: failed to merge worker_processes"
    exit 1
fi

echo '
nginx_config:
    worker_processes: ${{nproc}}
' > conf/config.yaml

out=$(nproc=false make init 2>&1 || true)
if ! echo "$out" | grep 'path\[nginx_config->worker_processes\] expect'; then
    echo "failed: failed to merge worker_processes"
    exit 1
fi

echo "passed: merge worker_processes"

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

# check the 'worker_shutdown_timeout' in 'nginx.conf' .

make init

grep -E "worker_shutdown_timeout 240s" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: worker_shutdown_timeout in nginx.conf is required 240s"
    exit 1
fi

echo "passed: worker_shutdown_timeout in nginx.conf is ok"

# check the 'client_max_body_size' in 'nginx.conf' .

git checkout conf/config.yaml

echo '
nginx_config:
    http:
        client_max_body_size: 512m
' > conf/config.yaml

make init

if ! grep -E "client_max_body_size 512m" conf/nginx.conf > /dev/null; then
    echo "failed: client_max_body_size in nginx.conf doesn't change"
    exit 1
fi

echo "passed: client_max_body_size in nginx.conf is ok"

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

# check customized config.yaml is copied and reverted.

git checkout conf/config.yaml

echo "
apisix:
    admin_api_mtls:
        admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
        admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
    port_admin: 9180
    https_admin: true
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

echo '
apisix:
    ssl:
        ssl_session_tickets: true
' > conf/config.yaml

make init

count=`grep -c "ssl_session_tickets on;" conf/nginx.conf || true `
if [ $count -eq 0 ]; then
    echo "failed: ssl_session_tickets is on when ssl.ssl_session_tickets is true."
    exit 1
fi

echo "passed: disable ssl_session_tickets by default"

# support 3rd-party plugin
echo '
apisix:
    extra_lua_path: "\$prefix/example/?.lua"
    extra_lua_cpath: "\$prefix/example/?.lua"
plugins:
    - 3rd-party
stream_plugins:
    - 3rd-party
' > conf/config.yaml

rm logs/error.log
make init
make run

sleep 0.5
make stop

if grep "failed to load plugin [3rd-party]" logs/error.log > /dev/null; then
    echo "failed: 3rd-party plugin can not be loaded"
    exit 1
fi
echo "passed: 3rd-party plugin can be loaded"

# validate extra_lua_path
echo '
apisix:
    extra_lua_path: ";"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'invalid extra_lua_path'; then
    echo "failed: can't detect invalid extra_lua_path"
    exit 1
fi

echo "passed: detect invalid extra_lua_path"

# check restart with old nginx.pid exist
echo "-1" > logs/nginx.pid
out=$(./bin/apisix start 2>&1 || true)
if echo "$out" | grep "APISIX is running"; then
    rm logs/nginx.pid
    echo "failed: should ignore stale nginx.pid"
    exit 1
fi

rm logs/nginx.pid
echo "pass: ignore stale nginx.pid"

# check the keepalive related parameter settings in the upstream
git checkout conf/config.yaml

echo '
nginx_config:
  http:
    upstream:
      keepalive: 32
      keepalive_requests: 100
      keepalive_timeout: 6s
' > conf/config.yaml

make init

if ! grep "keepalive 32;" conf/nginx.conf > /dev/null; then
    echo "failed: 'keepalive 32;' not in nginx.conf"
    exit 1
fi

if ! grep "keepalive_requests 100;" conf/nginx.conf > /dev/null; then
    echo "failed: 'keepalive_requests 100;' not in nginx.conf"
    exit 1
fi

if ! grep "keepalive_timeout 6s;" conf/nginx.conf > /dev/null; then
    echo "failed: 'keepalive_timeout 6s;' not in nginx.conf"
    exit 1
fi

echo "passed: found the keepalive related parameter in nginx.conf"

# check the charset setting
git checkout conf/config.yaml

echo '
nginx_config:
  http:
    charset: gbk
' > conf/config.yaml

make init

if ! grep "charset gbk;" conf/nginx.conf > /dev/null; then
    echo "failed: 'charset gbk;' not in nginx.conf"
    exit 1
fi

echo "passed: found the 'charset gbk;' in nginx.conf"

# check realip recursive setting
git checkout conf/config.yaml

echo '
nginx_config:
    http:
        real_ip_recursive: "on"
' > conf/config.yaml

make init

if ! grep "real_ip_recursive on;" conf/nginx.conf > /dev/null; then
    echo "failed: 'real_ip_recursive on;' not in nginx.conf"
    exit 1
fi

echo "passed: found 'real_ip_recursive on' in nginx.conf"

# check the variables_hash_max_size setting
git checkout conf/config.yaml

echo '
nginx_config:
  http:
    variables_hash_max_size: 1024
' > conf/config.yaml

make init

if ! grep "variables_hash_max_size 1024;" conf/nginx.conf > /dev/null; then
    echo "failed: 'variables_hash_max_size 1024;' not in nginx.conf"
    exit 1
fi

echo "passed: found the 'variables_hash_max_size 1024;' in nginx.conf"

# check the stream lua_shared_dict lrucache_lock value
git checkout conf/config.yaml

echo '
apisix:
  stream_proxy:
    tcp:
      - addr: 9100
        tls: true
      - addr: "127.0.0.1:9101"
    udp:
      - 9200
      - "127.0.0.1:9201"
nginx_config:
  stream:
    lua_shared_dict:
      lrucache-lock-stream: 20m
' > conf/config.yaml

make init

if ! grep "lrucache-lock-stream 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'lrucache-lock-stream 20m;' not in nginx.conf"
    exit 1
fi

echo "passed: found the 'lrucache-lock-stream 20m;' in nginx.conf"

# check the http lua_shared_dict variables value
git checkout conf/config.yaml

echo '
nginx_config:
  http:
    lua_shared_dict:
      internal-status: 20m
      plugin-limit-req: 20m
      plugin-limit-count: 20m
      prometheus-metrics: 20m
      plugin-limit-conn: 20m
      upstream-healthcheck: 20m
      worker-events: 20m
      lrucache-lock: 20m
      balancer-ewma: 20m
      balancer-ewma-locks: 20m
      balancer-ewma-last-touched-at: 20m
      plugin-limit-count-redis-cluster-slot-lock: 2m
      tracing_buffer: 20m
      plugin-api-breaker: 20m
      etcd-cluster-health-check: 20m
      discovery: 2m
      jwks: 2m
      introspection: 20m
      access-tokens: 2m
' > conf/config.yaml

make init

if ! grep "internal-status 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'internal-status 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "plugin-limit-req 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'plugin-limit-req 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "plugin-limit-count 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'plugin-limit-count 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "prometheus-metrics 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'prometheus-metrics 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "plugin-limit-conn 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'plugin-limit-conn 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "upstream-healthcheck 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'upstream-healthcheck 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "worker-events 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'worker-events 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "lrucache-lock 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'lrucache-lock 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "balancer-ewma 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'balancer-ewma 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "balancer-ewma-locks 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'balancer-ewma-locks 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "balancer-ewma-last-touched-at 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'balancer-ewma-last-touched-at 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "plugin-limit-count-redis-cluster-slot-lock 2m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'plugin-limit-count-redis-cluster-slot-lock 2m;' not in nginx.conf"
    exit 1
fi

if ! grep "tracing_buffer 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'tracing_buffer 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "plugin-api-breaker 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'plugin-api-breaker 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "etcd-cluster-health-check 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'etcd-cluster-health-check 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "discovery 2m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'discovery 2m;' not in nginx.conf"
    exit 1
fi

if ! grep "jwks 2m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'jwks 2m;' not in nginx.conf"
    exit 1
fi

if ! grep "introspection 20m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'introspection 20m;' not in nginx.conf"
    exit 1
fi

if ! grep "access-tokens 2m;" conf/nginx.conf > /dev/null; then
    echo "failed: 'access-tokens 2m;' not in nginx.conf"
    exit 1
fi

echo "passed: found the http lua_shared_dict related parameter in nginx.conf"
