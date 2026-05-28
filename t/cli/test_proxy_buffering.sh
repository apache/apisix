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

# Admin API curl wrapper
c() {
    method=${1^^}
    resource=$2
    shift 2
    local admin_key
    admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
    curl --fail-with-body ${ADMIN_SCHEME:-http}://${ADMIN_IP:-127.0.0.1}:${ADMIN_PORT:-9180}/apisix/admin${resource} \
    -H "X-API-KEY: ${admin_key}" -X "$method" "$@"
}

make run

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

timeout 10 python3 -u t/cli/test_sse.py

c put /routes/1 -d '{
    "uri": "/*",
    "plugins": {
        "proxy-buffering": {
            "disable_proxy_buffering": true
        }
    },
    "upstream": {
        "scheme": "http",
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'

timeout 10 python3 -u t/cli/test_sse.py

c delete /routes/1

make stop
