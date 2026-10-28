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

# a deterministic 80-byte key: a 16-byte name and 64 times the same letter
key() {
    printf 'ticket-name-%04d%s' "$1" "$(printf '%064d' 0 | tr 0 "$2")" | base64 -w0
}
k1=$(key 1 B)
k2=$(key 2 C)
record_key=/apisix/plugin_metadata/ssl-session-ticket

wait_for_status() {
    local pattern="$1"
    local deadline=$(( $(date +%s) + 20 ))
    { set +x; } 2>/dev/null
    while [ "$(date +%s)" -lt "$deadline" ]; do
        status="$(curl -s --max-time 2 http://127.0.0.1:9090/v1/tls_session_ticket || true)"
        if echo "$status" | grep -qE "$pattern"; then
            set -x
            return 0
        fi
        sleep 0.5
    done
    set -x
    echo "status: $status"
    return 1
}

# Stream only: no HTTP subsystem, no Admin API on this node
echo '
apisix:
    proxy_mode: stream
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
    ssl:
        ssl_session_tickets: true
    data_encryption:
        enable_encrypt_fields: false
nginx_config:
    meta:
        lua_shared_dict:
            tls-session-ticket: 2m
' > conf/config.yaml

make init

if ! grep -E 'lua_shared_dict tls-session-ticket 2m;' conf/nginx.conf > /dev/null; then
    echo "failed: the tls-session-ticket dict is not in the main-level lua block"
    exit 1
fi

if ! grep -E 'location = /v1/tls_session_ticket' conf/nginx.conf > /dev/null; then
    echo "failed: no control server in a stream-only deployment"
    exit 1
fi

etcdctl del "$record_key"
make run
wait_for_tcp 127.0.0.1 9090

etcdctl put "$record_key" "{\"id\":\"ssl-session-ticket\",\"keys\":[\"$k1\",\"$k2\"],\
\"origin\":{\"source\":\"external\",\"disabled\":false}}"

if ! wait_for_status '"key_count":2'; then
    echo "failed: the stream subsystem did not publish the keys"
    exit 1
fi

if ! echo "$status" | grep -q '"source":"external"'; then
    echo "failed: the status does not report the source"
    exit 1
fi

if echo "$status" | grep -q -e "$k1" -e "$k2"; then
    echo "failed: the status leaks the keys"
    exit 1
fi

# the routes of the HTTP subsystem are not there, nor other methods
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9090/v1/routes)
if [ "$code" != "404" ]; then
    echo "failed: unexpected status $code of /v1/routes"
    exit 1
fi

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:9090/v1/tls_session_ticket)
if [ "$code" != "404" ]; then
    echo "failed: unexpected status $code of POST /v1/tls_session_ticket"
    exit 1
fi

etcdctl del "$record_key"

if ! wait_for_status '"key_count":0.*' || echo "$status" | grep -q '"source":"external"'; then
    echo "failed: the deletion is not published"
    exit 1
fi

make stop

echo "passed: a stream-only deployment publishes and reports the TLS session ticket keys"

# with the stream prometheus exporter in the same minimal http block
echo '
apisix:
    proxy_mode: stream
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - prometheus
    - ssl-session-ticket
' > conf/config.yaml

make run
wait_for_tcp 127.0.0.1 9090
wait_for_tcp 127.0.0.1 9091

if ! wait_for_status '"warnings":\["default_keyring"\]'; then
    echo "failed: no status next to the prometheus exporter"
    exit 1
fi

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/apisix/prometheus/metrics)
if [ "$code" != "200" ]; then
    echo "failed: unexpected status $code of the prometheus exporter"
    exit 1
fi

make stop

echo "passed: the stream-only control server lives next to the prometheus exporter"
