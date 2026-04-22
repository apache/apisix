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
wait_for_tcp 127.0.0.1 9180
wait_for_tcp 127.0.0.1 9100

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

# Retry the trigger + read together. Two async conditions must both resolve:
#  1. The stream worker must pick up route 1 from etcd (otherwise the TCP
#     connection to 9100 is reset and the counter is never incremented).
#  2. The prometheus exporter timer must populate the shared-dict cache
#     (otherwise /prometheus/metrics returns 500 "data is nil").
# The counter may exceed 1 if multiple trigger curls succeed, so match any
# positive integer. Both curls are bounded so no single stall blows the budget.
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100 >/dev/null 2>&1 || true
    if curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
         | grep -qE 'apisix_stream_connection_total\{route="1"\} [1-9][0-9]*'; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
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
wait_for_tcp 127.0.0.1 9100

# Same retry rationale as the first block: trigger + read together until
# the stream route is live and the exporter cache is populated.
ok=0
deadline=$(( $(date +%s) + 20 ))
out=""
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100 >/dev/null 2>&1 || true
    # `|| true` so a curl failure here doesn't trip `set -e` via the command
    # substitution — we want to keep retrying until the deadline.
    out="$(curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics || true)"
    if echo "$out" | grep -qE 'apisix_stream_connection_total\{route="1"\} [1-9][0-9]*'; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: prometheus can't work in stream subsystem"
    exit 1
fi

if ! echo "$out" | grep "apisix_node_info{hostname=" > /dev/null; then
    echo "failed: prometheus can't work in stream subsystem"
    exit 1
fi

echo "passed: prometheus works when only stream is enabled"
