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

# data_plane accept quoted strings in config.yaml
echo '
deployment:
    role: "data_plane"
    role_data_plane:
        config_provider: yaml
' > conf/config.yaml

make run

sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes)
make stop

if [ ! $code -eq 404 ]; then
    echo "failed: quoted 'data_plane' role was not recognized"
    exit 1
fi

echo "passed: quoted 'data_plane' role was recognized"

echo '
deployment: { "role": "data_plane", "role_data_plane": { "config_provider": "yaml" } }
apisix:
    node_listen: 9080
' > conf/config.yaml

make run

sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes)
make stop

if [ ! $code -eq 404 ]; then
    echo "failed: flow style 'data_plane' role was not recognized"
    exit 1
fi

echo "passed: flow style configuration for 'data_plane' was recognized"