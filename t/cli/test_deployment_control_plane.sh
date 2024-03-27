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

get_admin_key() {
wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
local admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml)
echo "$admin_key"
}
export admin_key=$(get_admin_key); echo $admin_key

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key")

if [ ! $code -eq 200 ]; then
    echo "failed: control_plane should enable Admin API"
    exit 1
fi

echo "passed: control_plane should enable Admin API"

curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    },
    "uri": "/*"
}'

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/c -H "X-API-KEY: $admin_key")
make stop
if [ ! $code -eq 404 ]; then
    echo "failed: should disable request proxy"
    exit 1
fi

echo "passed: should disable request proxy"
