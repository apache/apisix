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

exit_if_not_customed_nginx

echo "
apisix:
    proxy_mode: http&stream
    enable_admin: true
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - prometheus
plugin_attr:
    prometheus:
        refresh_interval: 1
" > conf/config.yaml

make run

# Wait until the stream subsystem's prometheus exporter is ready by polling
# for the metric's HELP line, which appears once the stream plugin is loaded.
# Without this, the test is flaky on slow CI runners where `sleep 0.5` is not
# enough for the stream subsystem to come up after `make run`.
for _ in $(seq 1 20); do
    if curl -s --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
            2>/dev/null | grep -q "# HELP apisix_stream_connection_total"; then
        break
    fi
    sleep 0.5
done

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -v -k -i -m 20 -o /dev/null -s -X PUT http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
    -H "X-API-KEY: $admin_key" \
    -d '{
        "plugins": {
            "prometheus": {}
        },
        "upstream": {
            "type": "roundrobin",
            "nodes": [{
                "host": "127.0.0.1",
                "port": 1995,
                "weight": 1
            }]
        }
    }'

curl http://127.0.0.1:9100 || true
sleep 1 # wait for sync

out="$(curl http://127.0.0.1:9091/apisix/prometheus/metrics)"
if ! echo "$out" | grep "apisix_stream_connection_total{route=\"1\"} 1" > /dev/null; then
    echo "failed: prometheus can't work in stream subsystem"
    exit 1
fi

make stop

echo "passed: prometheus works when both http & stream are enabled"

echo "
apisix:
    proxy_mode: stream
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - prometheus
plugin_attr:
    prometheus:
        refresh_interval: 1
" > conf/config.yaml

make run

# Same readiness wait as above, since admin is disabled here we can't probe
# admin API; the prometheus HELP line is still a reliable readiness signal.
for _ in $(seq 1 20); do
    if curl -s --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
            2>/dev/null | grep -q "# HELP apisix_stream_connection_total"; then
        break
    fi
    sleep 0.5
done

curl http://127.0.0.1:9100 || true
sleep 1 # wait for sync

out="$(curl http://127.0.0.1:9091/apisix/prometheus/metrics)"
if ! echo "$out" | grep "apisix_stream_connection_total{route=\"1\"} 1" > /dev/null; then
    echo "failed: prometheus can't work in stream subsystem"
    exit 1
fi

if ! echo "$out" | grep "apisix_node_info{hostname=" > /dev/null; then
    echo "failed: prometheus can't work in stream subsystem"
    exit 1
fi

echo "passed: prometheus works when only stream is enabled"
