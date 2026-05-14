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

set -euo pipefail

# Admin API curl wrapper
# c [get|put|post|delete|...] <resource path> <any curl args> ...
c() {
    method=${1^^}
    resource=$2
    shift 2
    curl --fail-with-body ${ADMIN_SCHEME:-http}://${ADMIN_IP:-127.0.0.1}:${ADMIN_PORT:-9180}/apisix/admin${resource} \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X "$method" "$@"
}

c put /routes/1 -d '{
    "uri": "/*",
    "upstream": {
        "scheme": "http",
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'

timeout 10 python3 -u ci/test_sse.py

c put /ssls/1 -d '{
    "cert": "'"$(<t/certs/server.crt)"'",
    "key": "'"$(<t/certs/server.key)"'",
    "snis": [
        "localhost"
    ]
}'

c put /routes/1 -d '{
    "uri": "/*",
    "plugins": {
        "proxy-buffering": {
            "disable_proxy_buffering": true
        }
    },
    "upstream": {
        "scheme": "https",
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'

timeout 10 python3 -u ci/test_sse.py ssl
