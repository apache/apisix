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

# The 'admin.apisix.dev' is injected by ci/common.sh@set_coredns
echo '
apisix:
    enable_admin: false
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
' > conf/config.yaml

make run
sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')

if [ ! $code -eq 200 ]; then
    echo "failed: control_plane should enable Admin API"
    exit 1
fi

echo "passed: control_plane should enable Admin API"

curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/c -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
make stop
if [ ! $code -eq 404 ]; then
    echo "failed: should disable request proxy"
    exit 1
fi

echo "passed: should disable request proxy"
