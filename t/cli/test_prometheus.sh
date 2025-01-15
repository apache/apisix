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

sleep 1

make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/prometheus/metrics)
if [ ! $code -eq 404 ]; then
    echo "failed: should listen at default prometheus address"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9091/apisix/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen at default prometheus address"
    exit 1
fi

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "apisix_nginx_http_current_connections" > /dev/null; then
    echo "failed: should listen at default prometheus address"
    exit 1
fi

make stop

echo "passed: should listen at default prometheus address"

echo '
plugin_attr:
  prometheus:
    export_addr:
        ip: ${{IP}}
        port: ${{PORT}}
' > conf/config.yaml

IP=127.0.0.1 PORT=9092 make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9092/apisix/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen at configured prometheus address"
    exit 1
fi

make stop

echo "passed: should listen at configured prometheus address"

echo '
plugin_attr:
  prometheus:
    enable_export_server: false
    export_uri: /prometheus/metrics
    export_addr:
        ip: ${{IP}}
        port: ${{PORT}}
' > conf/config.yaml

IP=127.0.0.1 PORT=9092 make run

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
# initialize prometheus metrics public API route #1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} -X PUT http://127.0.0.1:9180/apisix/admin/routes/metrics1 \
    -H "X-API-KEY: $admin_key" \
    -d "{
        \"uri\": \"/prometheus/metrics\",
        \"plugins\": {
            \"public-api\": {}
        }
    }")
if [ ! $code -eq 201 ]; then
    echo "failed: initialize prometheus metrics public API failed #1"
    exit 1
fi

sleep 0.5

code=$(curl -v -k -i -m 20 -o /dev/null -s http://127.0.0.1:9092/prometheus/metrics || echo 'ouch')
if [ "$code" != "ouch" ]; then
    echo "failed: should listen at previous prometheus address"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen at previous prometheus address"
    exit 1
fi

make stop

echo "passed: should listen at previous prometheus address"

echo '
plugin_attr:
  prometheus:
    export_addr:
      ip: ${{IP}}
      port: ${{PORT}}
' > conf/config.yaml

out=$(IP=127.0.0.1 PORT=9090 make init 2>&1 || true)
if ! echo "$out" | grep "prometheus port 9090 conflicts with control"; then
    echo "failed: can't detect port conflicts"
    exit 1
fi

echo '
apisix:
  node_listen: ${{PORT}}
plugin_attr:
  prometheus:
    export_addr:
      ip: ${{IP}}
      port: ${{PORT}}
' > conf/config.yaml

out=$(IP=127.0.0.1 PORT=9092 make init 2>&1 || true)
if ! echo "$out" | grep "http listen port 9092 conflicts with prometheus"; then
    echo "failed: can't detect port conflicts"
    exit 1
fi

echo "passed: should detect port conflicts"

echo '
plugin_attr:
  prometheus:
    metric_prefix: apisix_ci_prefix_
    export_addr:
      ip: ${{IP}}
      port: ${{PORT}}
' > conf/config.yaml

IP=127.0.0.1 PORT=9092 make run

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
# initialize prometheus metrics public API route #2
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} -X PUT http://127.0.0.1:9180/apisix/admin/routes/metrics2 \
    -H "X-API-KEY: $admin_key" \
    -d "{
        \"uri\": \"/apisix/prometheus/metrics\",
        \"plugins\": {
            \"public-api\": {}
        }
    }")
if [ ! $code -eq 201 ]; then
    echo "failed: initialize prometheus metrics public API failed #2"
    exit 1
fi

sleep 0.5

if ! curl -s http://127.0.0.1:9092/apisix/prometheus/metrics | grep "apisix_ci_prefix_" | wc -l; then
    echo "failed: should use custom metric prefix"
    exit 1
fi

make stop

echo "passed: should use custom metric prefix"
