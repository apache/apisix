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

# normal YAML format
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config.yaml

export APISIX_STAND_ALONE=true

if ! make init > /dev/null 2>&1; then
    echo "failed: normal YAML format 'role: data_plane' was rejected"
    exit 1
fi

echo "passed: normal YAML format accepted"

# double-quoted value
echo '
deployment:
    role: "data_plane"
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: double-quoted 'role: \"data_plane\"' was rejected"
    exit 1
fi

echo "passed: double-quoted format accepted"

# single-quoted value
echo "
deployment:
    role: 'data_plane'
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
" > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: single quoted "role: 'data_plane'" was rejected"
    exit 1
fi

echo "passed: single-quoted format accepted"

# flow syntax
echo '
deployment: {"role": "data_plane", "role_data_plane": {"config_provider": "yaml"}}
apisix:
    node_listen: 9080
' > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: flow syntax was rejected"
    exit 1
fi

echo "passed: flow syntax accepted"

# JSON config_provider
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: json
apisix:
    node_listen: 9080
' > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: 'config_provider: json' was rejected"
    exit 1
fi

echo "passed: 'config_provider: json' accepted"

# should fail - etcd config_provider with APISIX_STAND_ALONE=true
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
          - "http://127.0.0.1:2379"
apisix:
    node_listen: 9080
' > conf/config.yaml

make clean > /dev/null 2>&1

if make init > /dev/null 2>&1; then
    echo "failed: 'config_provider: etcd' with APISIX_STAND_ALONE=true should be rejected"
    exit 1
fi

echo "passed: 'config_provider: etcd' was correctly rejected in standalone mode"

# traditional role with yaml config_provider
echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key_required: false
apisix:
    node_listen: 9080
    enable_admin: true
' > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: 'role: traditional' with 'config_provider: yaml' was rejected"
    exit 1
fi

echo "passed: 'role: traditional' with 'config_provider: yaml' accepted"

# without APISIX_STAND_ALONE env var, etcd should be allowed
unset APISIX_STAND_ALONE

echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
          - "http://127.0.0.1:2379"
apisix:
    node_listen: 9080
' > conf/config.yaml

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: 'config_provider: etcd' without APISIX_STAND_ALONE env var was rejected"
    exit 1
fi

echo "passed: 'config_provider: etcd' without APISIX_STAND_ALONE env var accepted"

# check APISIX_PROFILE is respected
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config-prod.yaml

echo 'routes: []
#END' > conf/apisix.yaml

export APISIX_PROFILE=prod
export APISIX_STAND_ALONE=true

make clean > /dev/null 2>&1

if ! make init > /dev/null 2>&1; then
    echo "failed: APISIX_PROFILE=prod is not respected in standalone mode"
    exit 1
fi

unset APISIX_PROFILE=prod
unset APISIX_STAND_ALONE=true
rm -f conf/config-prod.yaml conf/apisix-prod.yaml

echo "passed: APISIX_PROFILE=prod is respected in standalone mode"