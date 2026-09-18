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

# Plugin load / unload against a real gateway process, with the configuration
# served by the standalone Admin API rather than etcd. The reconciliation timer
# in admin/init.lua is registered in this mode as well, because /v1/plugins/reload
# stays reachable here and its broadcast has no delivery guarantee.

. ./t/cli/common.sh

ADMIN_KEY=edd1c9f034335f136f87ad84b625c8f1

write_config() {
    # $1: the plugin list body
    echo "
apisix:
    node_listen: 9080
    enable_admin: true
    enable_control: true
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        allow_admin:
            - 127.0.0.0/24
        admin_key:
            - name: admin
              key: $ADMIN_KEY
              role: admin
nginx_config:
    error_log_level: info
plugins:
$1
" > conf/config.yaml
}

# Port 9 (discard) is never listening, so the status tells the two states apart
# without needing a backend: 401 means key-auth ran and rejected the request,
# 502 means the request got past the plugins and reached the proxy.
status_of() {
    curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:9080/hello"
}

# deadline-bounded, so the test does not depend on a fixed reload latency
wait_for_status() {
    local i
    { set +x; } 2>/dev/null
    for i in $(seq 1 50); do
        if [ "$(status_of)" = "$1" ]; then
            set -x
            return 0
        fi
        sleep 0.2
    done
    set -x
    echo "failed: $2 (last status: $(status_of))"
    exit 1
}

# prometheus is never loaded or unloaded here, it is in both lists because the
# prometheus-cache shared dict is only rendered when it is enabled at init time
# and error-log-logger reaches the exporter through its require chain
PLUGINS_ALL="    - key-auth
    - serverless-pre-function
    - public-api
    - prometheus
    - error-log-logger
    - node-status"
PLUGINS_MIN="    - serverless-pre-function
    - public-api
    - prometheus"

write_config "$PLUGINS_ALL"
make init
make run
wait_for_tcp 127.0.0.1 9180

curl -s -o /dev/null -XPUT "http://127.0.0.1:9180/apisix/admin/configs" \
    -H "X-API-KEY: $ADMIN_KEY" -H "X-Digest: reload-1" \
    -d '{
        "routes": [
            {
                "id": "r1",
                "uri": "/hello",
                "plugins": {"key-auth": {}},
                "upstream": {"nodes": {"127.0.0.1:9": 1}, "type": "roundrobin"}
            },
            {
                "id": "bump",
                "uri": "/bump",
                "plugins": {
                    "serverless-pre-function": {
                        "phase": "rewrite",
                        "functions": [
                            "return function() ngx.shared[\"internal-status\"]:incr(\"plugins_conf_version\", 1, 0) ngx.exit(200) end"
                        ]
                    }
                },
                "upstream": {"nodes": {"127.0.0.1:9": 1}, "type": "roundrobin"}
            },
            {
                "id": "status",
                "uri": "/apisix/status",
                "plugins": {"public-api": {}},
                "upstream": {"nodes": {"127.0.0.1:9": 1}, "type": "roundrobin"}
            }
        ],
        "consumers": [
            {"username": "jack", "plugins": {"key-auth": {"key": "jack-key"}}}
        ]
    }'

wait_for_status 401 "key-auth should reject an unauthenticated request"

echo "passed: key-auth is in effect on a standalone configuration"

echo "unloading key-auth"
write_config "$PLUGINS_MIN"
curl -s -o /dev/null -XPUT http://127.0.0.1:9090/v1/plugins/reload

wait_for_status 502 "the request should reach the proxy once key-auth is unloaded"

echo "passed: key-auth was unloaded by a reload"

echo "loading key-auth again"
write_config "$PLUGINS_ALL"
curl -s -o /dev/null -XPUT http://127.0.0.1:9090/v1/plugins/reload

wait_for_status 401 "key-auth should be in effect again after reloading it"

echo "passed: key-auth was loaded again by a reload"

if grep -q "sync local conf to etcd" logs/error.log; then
    echo "failed: standalone has no etcd, the reload path must not sync to it"
    exit 1
fi

echo "passed: no etcd sync was attempted"


# --- missed-event reconciliation -------------------------------------------
#
# The events broadcast has no delivery guarantee: a worker that is (re)connecting
# to the broker loses the event for good and is left running the plugins of the
# previous list. GET /bump reproduces that state deterministically -- it advances
# plugins_conf_version exactly the way a reload does, but posts no event -- so
# only the reconciliation timer in admin/init.lua can converge the workers.

# a plugin's api() routes live in a module-level registry that is rebuilt by
# plugin.load(), so this tells a real reload from a per-route plugin lookup
status_of_uri() {
    curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:9080$1"
}

wait_for_uri_status() {
    local i
    { set +x; } 2>/dev/null
    for i in $(seq 1 50); do
        if [ "$(status_of_uri "$1")" = "$2" ]; then
            set -x
            return 0
        fi
        sleep 0.2
    done
    set -x
    echo "failed: $3 (last status: $(status_of_uri "$1"))"
    exit 1
}

timer_runs_since() {
    # $1: byte offset in the error log to count from
    tail -c "+$1" logs/error.log | grep -c "run timer\[plugin#error-log-logger\]" || true
}

if [ "$(status_of_uri /apisix/status)" = "404" ]; then
    echo "failed: node-status is loaded, its api route should be registered"
    exit 1
fi

# the background timer runs once a second, so this is bounded, not a race
sleep 2
if [ "$(timer_runs_since 1)" = "0" ]; then
    echo "failed: error-log-logger is loaded, its timer should be running"
    exit 1
fi

echo "passed: the plugin api route and the plugin timer are both live"

echo "dropping the plugins without broadcasting the reload"
write_config "$PLUGINS_MIN"
curl -s -o /dev/null "http://127.0.0.1:9080/bump"

wait_for_status 502 "the reconciliation timer should unload key-auth without an event"

echo "passed: a version-behind worker converged on its own"

wait_for_uri_status /apisix/status 404 "plugin.load() should have dropped the node-status api route"

echo "passed: the plugin api registry was rebuilt, not just the route lookup"

offset=$(( $(wc -c < logs/error.log) + 1 ))
sleep 3
if [ "$(timer_runs_since $offset)" != "0" ]; then
    echo "failed: error-log-logger was unloaded, its timer must not still run"
    exit 1
fi

echo "passed: no stale plugin timer survived the unload"

echo "restoring the plugins without broadcasting the reload"
write_config "$PLUGINS_ALL"
offset=$(( $(wc -c < logs/error.log) + 1 ))
curl -s -o /dev/null "http://127.0.0.1:9080/bump"

wait_for_status 401 "the reconciliation timer should load key-auth back without an event"
wait_for_uri_status /apisix/status 200 "the node-status api route should be registered again"

sleep 2
if [ "$(timer_runs_since $offset)" = "0" ]; then
    echo "failed: error-log-logger was loaded again, its timer should run again"
    exit 1
fi

echo "passed: the reverse transition converged the same way"
