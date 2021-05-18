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

echo "passed: access_log_format in nginx.conf is ok"

# check enable access log

echo '
nginx_config:
  http:
    enable_access_log: true
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host test_enable_access_log_true"
' > conf/config.yaml

make init

count_test_access_log=`grep -c "test_enable_access_log_true" conf/nginx.conf || true`
if [ $count_test_access_log -eq 0 ]; then
    echo "failed: nginx.conf file doesn't find access_log_format when enable access log"
    exit 1
fi

count_access_log_off=`grep -c "access_log off;" conf/nginx.conf || true`
if [ $count_access_log_off -eq 4 ]; then
    echo "failed: nginx.conf file find access_log off; when enable access log"
    exit 1
fi

make run
sleep 0.1
curl http://127.0.0.1:9080/hi
sleep 4
tail -n 1 logs/access.log > output.log

count_grep=`grep -c "test_enable_access_log_true" output.log || true`
if [ $count_grep -eq 0 ]; then
    echo "failed: not found test_enable_access_log in access.log "
    exit 1
fi

make stop

echo '
nginx_config:
  http:
    enable_access_log: false
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host test_enable_access_log_false"
' > conf/config.yaml

make init

count_test_access_log=`grep -c "test_enable_access_log_false" conf/nginx.conf || true`
if [ $count_test_access_log -eq 1 ]; then
    echo "failed: nginx.conf file find access_log_format when disable access log"
    exit 1
fi

count_access_log_off=`grep -c "access_log off;" conf/nginx.conf || true`
if [ $count_access_log_off -ne 4 ]; then
    echo "failed: nginx.conf file doesn't find access_log off; when disable access log"
    exit 1
fi

make run
sleep 0.1
curl http://127.0.0.1:9080/hi
sleep 4
tail -n 1 logs/access.log > output.log

count_grep=`grep -c "test_enable_access_log_false" output.log || true`
if [ $count_grep -eq 1 ]; then
    echo "failed: found test_enable_access_log in access.log "
    exit 1
fi

make stop

echo "passed: enable_access_log is ok"

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

# check uninitialized variable in access log when access admin
git checkout conf/config.yaml

rm logs/error.log
make init
make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: failed to access admin"
    exit 1
fi

if grep -E 'using uninitialized ".+" variable while logging request' logs/error.log; then
    echo "failed: uninitialized variable found during writing access log"
    exit 1
fi

echo "pass: uninitialized variable not found during writing access log"

# don't log uninitialized access log variable when the HTTP request is malformed

git checkout conf/config.yaml

rm logs/error.log
./bin/apisix start
sleep 1 # wait for apisix starts

curl -v -k -i -m 20 -o /dev/null -s https://127.0.0.1:9080 || true
if grep -E 'using uninitialized ".+" variable while logging request' logs/error.log; then
    echo "failed: log uninitialized access log variable when the HTTP request is malformed"
    exit 1
fi

make stop

echo "don't log uninitialized access log variable when the HTTP request is malformed"

# TLS upstream

echo "
apisix:
    admin_api_mtls:
        admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
        admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
    port_admin: 9180
    https_admin: true
nginx_config:
  http:
    access_log_format: '\"\$upstream_scheme://\$upstream_host\" \$ssl_server_name'
" > conf/config.yaml

make run
sleep 2

curl -k -i https://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d \
    '{"uri":"/apisix/admin/routes/1", "upstream":{"nodes":{"localhost:9180":1},"scheme":"https","type":"roundrobin","pass_host":"node"}}'

curl -i http://127.0.0.1:9080/apisix/admin/routes/1
sleep 4
tail -n 2 logs/access.log > output.log

# APISIX
if ! grep '"https://localhost" -' output.log; then
    echo "failed: should find upstream scheme"
    cat output.log
    exit 1
fi

# admin
if ! grep '"http://localhost" localhost' output.log; then
    echo "failed: should find upstream scheme"
    cat output.log
    exit 1
fi

make stop
echo "passed: should find upstream scheme"
