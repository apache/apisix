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

# control server
echo '
apisix:
  enable_control: true
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.1:9090;" conf/nginx.conf > /dev/null; then
    echo "failed: find default address for control server"
    exit 1
fi

make run

sleep 0.1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9090/v1/schema)

if [ ! $code -eq 200 ]; then
    echo "failed: access control server"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9090/v0/schema)

if [ ! $code -eq 404 ]; then
    echo "failed: handle route not found"
    exit 1
fi

make stop

echo '
apisix:
  enable_control: true
  control:
    ip: 127.0.0.2
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.2:9090;" conf/nginx.conf > /dev/null; then
    echo "failed: customize address for control server"
    exit 1
fi

make run

sleep 0.1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.2:9090/v1/schema)

if [ ! $code -eq 200 ]; then
    echo "failed: access control server"
    exit 1
fi

make stop

echo '
apisix:
  enable_control: true
  control:
    port: 9092
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.1:9092;" conf/nginx.conf > /dev/null; then
    echo "failed: customize address for control server"
    exit 1
fi

make run

sleep 0.1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9092/v1/schema)

if [ ! $code -eq 200 ]; then
    echo "failed: access control server"
    exit 1
fi

make stop

echo '
apisix:
  enable_control: false
' > conf/config.yaml

make init

if grep "listen 127.0.0.1:9090;" conf/nginx.conf > /dev/null; then
    echo "failed: disable control server"
    exit 1
fi

echo '
apisix:
  node_listen: 9090
  enable_control: true
  control:
    port: 9090
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "node_listen port conflicts with control, prometheus, etc."; then
    echo "failed: can't detect port conflicts"
    exit 1
fi

echo '
apisix:
  node_listen: 9080
  enable_control: true
  control:
    port: 9091
plugin_attr:
  prometheus:
    export_addr:
      ip: "127.0.0.1"
      port: 9091
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "prometheus port conflicts with control, node_listen, etc."; then
    echo "failed: can't detect port conflicts"
    exit 1
fi

echo "pass: access control server"
