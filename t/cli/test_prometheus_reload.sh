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

make run

sleep 2

echo "removing prometheus from the plugins list"
echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - ip-restriction' > conf/config.yaml

echo "fetch metrics, should not contain {}"

if curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should not contain '{}' when prometheus is enabled"
    exit 1
fi

echo "calling reload API to actually disable prometheus"

curl -i http://127.0.0.1:9090/v1/plugins/reload -XPUT

sleep 2

echo "fetch metrics after reload should contain {}"

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should contain '{}' when prometheus is disabled"
    exit 1
fi

echo "re-enable prometheus"

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - prometheus' > conf/config.yaml

echo "fetching metrics without reloading should give same result as before"

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should contain '{}' when prometheus is disabled"
    exit 1
fi

echo "calling reload API to actually enable prometheus"

curl -i http://127.0.0.1:9090/v1/plugins/reload -XPUT

sleep 2

if curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should not contain '{}' when prometheus is enabled"
    exit 1
fi

# The per-process metrics follow the plugin through hot reloads: each process
# runs exactly one reporting timer while prometheus is enabled and none while
# it is disabled.
make stop
sleep 0.5
rm logs/error.log || true

write_conf() {
    echo "
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
nginx_config:
  error_log_level: info
  worker_processes: $1
plugins:
  - $2
plugin_attr:
  prometheus:
    refresh_interval: 1
" > conf/config.yaml
}

# wait_for <description> <command...>: polls for up to 20 seconds
wait_for() {
    local desc=$1
    shift
    local deadline=$(( $(date +%s) + 20 ))
    { set +x; } 2>/dev/null
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if "$@"; then
            set -x
            return 0
        fi
        sleep 0.5
    done
    set -x
    echo "failed: $desc"
    exit 1
}

metrics() {
    curl -s --connect-timeout 1 --max-time 2 http://127.0.0.1:9091/apisix/prometheus/metrics || true
}

# 2 workers and the privileged agent, http only
started_is() { [ "$(grep -c 'process metrics started' logs/error.log)" -eq "$1" ]; }
stopped_is() { [ "$(grep -c 'process metrics stopped' logs/error.log)" -eq "$1" ]; }
reports_workers() {
    local out
    out="$(metrics)"
    echo "$out" | grep -qE 'apisix_nginx_lua_memory_bytes\{process="worker-0",subsystem="http"\} [0-9]' \
        && echo "$out" | grep -qE 'apisix_nginx_lua_memory_bytes\{process="worker-1",subsystem="http"\} [0-9]' \
        && echo "$out" | grep -qE 'apisix_nginx_lua_memory_bytes\{process="privileged-agent",subsystem="http"\} [0-9]'
}
exports_nothing() { metrics | grep -q "{}"; }

write_conf 2 prometheus
make run

wait_for "every process reports when prometheus is enabled" reports_workers
wait_for "one reporting timer per process" started_is 3

write_conf 2 ip-restriction
curl -s -o /dev/null http://127.0.0.1:9090/v1/plugins/reload -XPUT

wait_for "every reporting timer stops when prometheus is disabled" stopped_is 3
wait_for "nothing is exported when prometheus is disabled" exports_nothing

write_conf 2 prometheus
curl -s -o /dev/null http://127.0.0.1:9090/v1/plugins/reload -XPUT

wait_for "reporting resumes when prometheus is enabled again" started_is 6
wait_for "every process reports again" reports_workers

# reloading with prometheus still enabled keeps the running timer
curl -s -o /dev/null http://127.0.0.1:9090/v1/plugins/reload -XPUT
sleep 3
if ! started_is 6 || ! stopped_is 3; then
    echo "failed: a plugin reload must not start a second reporting timer"
    exit 1
fi

echo "passed: process metrics follow the plugin through hot reloads"

# Scaling down must not leave the series of the workers that are gone.
write_conf 1 prometheus
make reload

no_retired_worker() {
    local out
    out="$(metrics)"
    echo "$out" | grep -qE 'apisix_nginx_lua_memory_bytes\{process="worker-0",subsystem="http"\} [0-9]' \
        && ! echo "$out" | grep -q 'process="worker-1"'
}
wait_for "the series of a retired worker are removed" no_retired_worker

make stop

echo "passed: the series of retired workers are removed"
