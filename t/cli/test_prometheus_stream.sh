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

# Retry trigger + read: route-propagation and exporter-cache populate are both async.
# Counter can exceed 1 across retries, so match any positive integer.
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100 >/dev/null 2>&1 || true
    if curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
         | grep -qE 'apisix_stream_connection_total\{route="1",service="",service_id=""\} [1-9][0-9]*'; then
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

# Same retry pattern as the first block; `|| true` on the curl cmd-subst so curl
# failure mid-loop doesn't trip `set -e`.
ok=0
deadline=$(( $(date +%s) + 20 ))
out=""
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100 >/dev/null 2>&1 || true
    out="$(curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics || true)"
    if echo "$out" | grep -qE 'apisix_stream_connection_total\{route="1",service="",service_id=""\} [1-9][0-9]*'; then
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

# the http subsystem exists only to export metrics here, yet every process
# still reports its own Lua VMs and connection slots
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    out="$(curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics || true)"
    if echo "$out" | grep -qE 'apisix_nginx_timers\{process="worker-0",subsystem="stream",state="running"\} [0-9]+$' \
        && echo "$out" | grep -qE 'apisix_nginx_lua_memory_bytes\{process="privileged-agent",subsystem="http"\} [1-9]' \
        && echo "$out" | grep -qE 'apisix_nginx_process_connections_max\{process="privileged-agent"\} 512$'; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: process metrics are missing when only stream is enabled"
    exit 1
fi

echo "passed: process metrics work when only stream is enabled"

# the export-only http block runs on the same timer limits as the stream
# subsystem, so the reported limits hold for every Lua VM
http_block="$(sed -n '/^http {/,/^}/p' conf/nginx.conf)"
if ! echo "$http_block" | grep -q "lua_max_pending_timers 16384;" \
    || ! echo "$http_block" | grep -q "lua_max_running_timers 4096;"; then
    echo "failed: the stream-only http block does not carry the timer limits"
    exit 1
fi

if ! echo "$out" | grep -qE 'apisix_nginx_timers_max\{state="pending"\} 16384$'; then
    echo "failed: nginx_timers_max does not report the configured limit"
    exit 1
fi

echo "passed: the stream-only http block carries the timer limits"

# The plugin list can come from etcd instead of config.yaml, and it arrives long
# after nginx.conf has been rendered. The Admin API has to stay off for that:
# with it on, worker 0 overwrites /apisix/plugins from the local config at boot
# (apisix/admin/init.lua).
make stop
etcdctl del / --prefix

echo "
apisix:
    proxy_mode: http&stream
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
plugins:
    - ip-restriction
stream_plugins: []
nginx_config:
    worker_processes: 1
    error_log_level: info
plugin_attr:
    prometheus:
        refresh_interval: 1
" > conf/config.yaml

make init

if ! grep "apisix_stream_metrics_zone" conf/nginx.conf > /dev/null; then
    echo "failed: the stream metrics zone was gated on the config file plugin list"
    exit 1
fi

echo "passed: the stream metrics zone does not depend on the config file plugin list"

# proxied to the gateway's own HTTP port so the session carries real bytes both
# ways without a second upstream process to keep alive
etcdctl put /apisix/stream_routes/1 \
    '{"plugins":{"prometheus":{}},"upstream":{"type":"roundrobin","nodes":{"127.0.0.1:9080":1}}}'

make run
wait_for_tcp 127.0.0.1 9100

# Enable only the stream plugin after both subsystems have initialized.
etcdctl put /apisix/plugins '[{"name":"prometheus","stream":true}]'

# Same retry shape as the blocks above: the exporter cache populates async.
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100/ >/dev/null 2>&1 || true
    if curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
         | grep -qE 'apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:9100"[^}]*\} [1-9][0-9]*'; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: no L4 bandwidth metric when the plugin list comes from etcd"
    exit 1
fi

echo "passed: the L4 zone metrics work with an etcd owned plugin list"

# Disable both exporters, then restore the stream registry without reloading NGINX.
started_before=$(grep -c 'stream .*process metrics started' logs/error.log)
stopped_before=$(grep -c 'stream .*process metrics stopped' logs/error.log || true)
etcdctl put /apisix/plugins '[]'
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
         | grep -q '^{}$' \
         && [ "$(grep -c 'stream .*process metrics stopped' logs/error.log || true)" -gt "$stopped_before" ]; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: exporters did not stop after disabling prometheus"
    exit 1
fi

etcdctl put /apisix/plugins '[{"name":"prometheus","stream":true}]'
ok=0
deadline=$(( $(date +%s) + 20 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9100/ >/dev/null 2>&1 || true
    if curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics \
         | grep -qE 'apisix_stream_connection_total\{route="1",service="",service_id=""\} [1-9][0-9]*' \
         && [ "$(grep -c 'stream .*process metrics started' logs/error.log)" -gt "$started_before" ]; then
        ok=1
        break
    fi
    sleep 0.5
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: stream metrics did not resume after re-enabling prometheus"
    exit 1
fi

echo "passed: stream prometheus can be disabled and re-enabled through etcd"
