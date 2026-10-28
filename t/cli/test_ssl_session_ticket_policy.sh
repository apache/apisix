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

# generated keys need etcd: standalone mode refuses them
echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
plugin_attr:
    ssl-session-ticket:
        enabled: true
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "invalid plugin_attr.ssl-session-ticket: generated keys need etcd, set key_source to external in standalone mode (config_provider yaml)"; then
    echo "failed: standalone mode should refuse generated keys"
    exit 1
fi

echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: json
plugin_attr:
    ssl-session-ticket:
        enabled: true
        key_source: generated
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "generated keys need etcd, set key_source to external in standalone mode (config_provider json)"; then
    echo "failed: standalone data plane should refuse generated keys"
    exit 1
fi

echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
plugin_attr:
    ssl-session-ticket:
        enabled: true
        key_source: external
' > conf/config.yaml

make init

echo "passed: standalone mode only supports external keys"

# the local policy is checked where it is executed
echo '
plugin_attr:
    ssl-session-ticket:
        key_source: imported
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'invalid plugin_attr.ssl-session-ticket: property "key_source" validation failed'; then
    echo "failed: an invalid key_source should be refused"
    exit 1
fi

echo '
plugin_attr:
    ssl-session-ticket:
        generated:
            rotation_interval: 30
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'invalid plugin_attr.ssl-session-ticket: property "generated" validation failed'; then
    echo "failed: a too short rotation_interval should be refused"
    exit 1
fi

# a data plane backed by etcd does not execute it
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - http://127.0.0.1:2379
plugin_attr:
    ssl-session-ticket:
        key_source: imported
' > conf/config.yaml

make init

echo "passed: the local policy is checked where it applies"
