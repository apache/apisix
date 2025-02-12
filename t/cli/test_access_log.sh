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
if [ $count_access_log_off -eq 5 ]; then
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

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
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
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
nginx_config:
  http:
    access_log_format: '\"\$upstream_scheme://\$upstream_host\" \$ssl_server_name'
" > conf/config.yaml

echo "check here:"
#check permission
# Add this before "make run" in the "TLS upstream" section
echo "CHECK HERE"
# Reset ownership to the user who invoked sudo
sudo chown "${SUDO_USER:-$(whoami)}":"${SUDO_USER:-$(whoami)}" conf/config.yaml
# Set secure permissions
sudo chmod 644 conf/config.yaml
ls -l conf/config.yaml
ls -ld conf/
make run
sleep 2

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -k -i https://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d \
    '{"uri":"/apisix/admin/routes/1", "upstream":{"nodes":{"localhost:9180":1},"scheme":"https","type":"roundrobin","pass_host":"node"}}'

curl -i http://127.0.0.1:9080/apisix/admin/routes/1
sleep 4
tail -n 2 logs/access.log > output.log

# APISIX
if ! grep '"https://localhost:9180" -' output.log; then
    echo "failed: should find upstream scheme"
    cat output.log
    exit 1
fi

# admin
if ! grep '"http://localhost:9180" localhost' output.log; then
    echo "failed: should find upstream scheme"
    cat output.log
    exit 1
fi

make stop
echo "passed: should find upstream scheme"

# check stream logs
echo '
apisix:
    proxy_mode: stream
    stream_proxy:                  # UDP proxy
     udp:
       - "127.0.0.1:9200"

nginx_config:
  stream:
    enable_access_log: true
    access_log_format: "$remote_addr $protocol test_stream_access_log_format"
' > conf/config.yaml

make init

grep "test_stream_access_log_format" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: stream access_log_format in nginx.conf doesn't change"
    exit 1
fi
echo "passed: stream access_log_format in nginx.conf is ok"

# check if logs are being written
make run
sleep 0.1
# sending single udp packet
echo -n "hello" | nc -4u -w1 localhost 9200
sleep 4
tail -n 1 logs/access_stream.log > output.log

if ! grep '127.0.0.1 UDP test_stream_access_log_format' output.log; then
    echo "failed: should have found udp log entry"
    cat output.log
    exit 1
fi
echo "passed: logs are being dumped for stream proxy"
