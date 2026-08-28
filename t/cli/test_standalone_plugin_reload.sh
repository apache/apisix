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

write_config "    - key-auth"
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
            }
        ],
        "consumers": [
            {"username": "jack", "plugins": {"key-auth": {"key": "jack-key"}}}
        ]
    }'

wait_for_status 401 "key-auth should reject an unauthenticated request"

echo "passed: key-auth is in effect on a standalone configuration"

echo "unloading key-auth"
write_config "    - ip-restriction"
curl -s -o /dev/null -XPUT http://127.0.0.1:9090/v1/plugins/reload

wait_for_status 502 "the request should reach the proxy once key-auth is unloaded"

echo "passed: key-auth was unloaded by a reload"

echo "loading key-auth again"
write_config "    - key-auth"
curl -s -o /dev/null -XPUT http://127.0.0.1:9090/v1/plugins/reload

wait_for_status 401 "key-auth should be in effect again after reloading it"

echo "passed: key-auth was loaded again by a reload"

if grep -q "sync local conf to etcd" logs/error.log; then
    echo "failed: standalone has no etcd, the reload path must not sync to it"
    exit 1
fi

echo "passed: no etcd sync was attempted"
