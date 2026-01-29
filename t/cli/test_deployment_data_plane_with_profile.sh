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

echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        host:
            - "http://127.0.0.1:2379"
        prefix: "/apisix"
apisix:
    node_listen: 9080
' > conf/config.yaml

echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config-prod.yaml

echo '
routes: []
#END' > conf/apisix-prod.yaml

export APISIX_PROFILE=prod

make run

sleep 1

proxy_code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes)
admin_exit_code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes || true)

make stop
unset APISIX_PROFILE

if [ "$proxy_code" -ne 404 ]; then
    echo "failed: proxy port 9080 did not start. Got HTTP code: $proxy_code"
    exit 1
fi

if [ "$admin_exit_code" -ne 000 ]; then
    echo "failed: Admin API port 9180 is OPEN. APISIX ignored the profile and loaded config.yaml (traditional)."
    exit 1
fi

echo "passed: APISIX_PROFILE=prod was respected by loading config-prod.yaml"
